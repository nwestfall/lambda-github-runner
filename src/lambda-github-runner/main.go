package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-lambda-go/lambdacontext"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
)

// RunnerEvent is the event passed in
type RunnerEvent struct {
	QueueURL     string `json:"queue_url"`
	RepoURL      string `json:"repo_url"`
	RepoFullName string `json:"repo_fullname"`
	Token        string `json:"token"`
	VirtualID    string `json:"virtual_id"`
	Event        string `json:"event"`
}

// RunnerToken is the token used for the github runner
type RunnerToken struct {
	Token string `json:"token"`
}

// HandleRequest handles the lambda request
func HandleRequest(ctx context.Context, event RunnerEvent) (string, error) {
	defer func() {
		if e := recover(); e != nil {
			fmt.Println("Recovered from panic", e)
		}
	}()

	tempToken := event.Token
	event.Token = "******"
	fmt.Println(event)
	event.Token = tempToken

	lc, _ := lambdacontext.FromContext(ctx)
	fmt.Println("Getting runner token")
	client := http.Client{
		Timeout: time.Duration(30 * time.Second),
	}
	url := "https://api.github.com/repos/" + event.RepoFullName + "/actions/runners/registration-token"
	fmt.Println(url)
	request, _ := http.NewRequest("POST", url, nil)
	request.Header.Set("Accept", "application/vnd.github.v3+json")
	request.Header.Set("Authorization", "token "+event.Token)
	request.Header.Set("User-Agent", "lambda-github-runner")
	resp, err := client.Do(request)
	if err != nil || resp.StatusCode != 201 {
		fmt.Println("Unable to get runner registrtation token", err)
		fmt.Println(resp)
		return "Unable to get runner registration token", err
	}
	defer resp.Body.Close()
	regToken := RunnerToken{}
	regData, _ := ioutil.ReadAll(resp.Body)
	json.Unmarshal(regData, &regToken)

	fmt.Println("Move runner directory to lambda /tmp")
	err = os.Mkdir("/tmp/runner", 0755)
	if os.IsExist(err) == false {
		err = copy("/runner", "/tmp/runner")
		if err != nil {
			fmt.Println("Unable to copy runner", err)
			return "Unable to copy runner", err
		}
	}
	err = os.Mkdir("/tmp/toolcache", 0755)

	fmt.Println("Removing runner in case one already exists")
	err = stopAndDecomissionRunner(regToken)
	if err != nil {
		fmt.Printf("Unable to remove runner, going to continue anyway\n", err)
	}

	fmt.Printf("Configuring runner (Request: %s|RepoUrl: %s|RepoFullName: %s|QueueUrl: %s)...\n", lc.AwsRequestID, event.RepoURL, event.RepoFullName, event.QueueURL)
	runnerName := "lambda-" + lc.AwsRequestID
	if event.Event == "create" {
		runnerName = "DEFAULT-LAMBDA-DO-NOT-REMOVE"
		fmt.Println("Creating default runner")
	}

	configcmd := exec.Command("/tmp/runner/config.sh", "--url", event.RepoURL, "--token", regToken.Token, "--name", runnerName, "--runnergroup", "lambda", "--labels", "lambda", "--work", "_work", "--replace")
	out, err := configcmd.Output()
	if err != nil {
		fmt.Println(string(out), err)
		readRunnerLogs()
		return fmt.Sprint(out), err
	}
	if os.Getenv("ALWAYS_PRINT_LOGS") == "true" {
		readRunnerLogs()
	}

	// if event is 'created', bail after configured
	if event.Event == "create" {
		fmt.Println("This is a create event, stopping runner")
		return fmt.Sprint("Runner created"), nil
	}

	fmt.Println("Starting runner...")
	err = startRunner()
	if err != nil {
		return fmt.Sprint("Unable to start runner"), err
	}

	fmt.Println("Runner started...")
	// Setup Virtual Queue and wait for Message
	sess := session.Must(session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	}))

	svc := sqs.New(sess)
	fmt.Println("Starting to listener for complete message")
	for {
		msgResult, err := svc.ReceiveMessage(&sqs.ReceiveMessageInput{
			AttributeNames: []*string{
				aws.String(sqs.MessageSystemAttributeNameSentTimestamp),
			},
			MessageAttributeNames: []*string{
				aws.String(sqs.QueueAttributeNameAll),
			},
			QueueUrl:            aws.String(event.QueueURL),
			MaxNumberOfMessages: aws.Int64(1),
			VisibilityTimeout:   aws.Int64(60),
		})

		if err != nil {
			fmt.Println("Error while receiving messages", err)
		}

		if len(msgResult.Messages) > 0 {
			if strings.Compare(*msgResult.Messages[0].Body, event.VirtualID) == 0 {
				fmt.Println("Message received, closing runner")
				_, err = svc.DeleteMessage(&sqs.DeleteMessageInput{
					QueueUrl:      aws.String(event.QueueURL),
					ReceiptHandle: msgResult.Messages[0].ReceiptHandle,
				})
				if err != nil {
					fmt.Println("Error while deleting message", err)
				}
				break
			}
		}

		deadline, _ := ctx.Deadline()
		deadline = deadline.Add(-30 * time.Second)

		if time.Until(deadline).Seconds() < 0 {
			fmt.Println("Function is about to timeout, decomissioning")
			break
		}
	}

	err = stopAndDecomissionRunner(regToken)

	fmt.Println("Complete!")
	return fmt.Sprint("Complete!"), err
}

// startRunner starts the github runner
func startRunner() error {
	runcmd := exec.Command("/tmp/runner/run.sh")
	// Something with output
	return runcmd.Start()
}

// stopAndDecomissionRunner stops and removes the runner
func stopAndDecomissionRunner(event RunnerToken) error {
	fmt.Println("Removing runner...")
	configcmd := exec.Command("/tmp/runner/config.sh", "remove", "--token", event.Token)
	_, err := configcmd.Output()
	if err != nil {
		fmt.Println("Unable to remove runner", err)
		return err
	}
	fmt.Println("Runner removed")
	return nil
}

// readRunnerLogs reads the runners logs to console
func readRunnerLogs() {
	fmt.Println("Reading logs...")
	// Try to get logs
	files, _ := ioutil.ReadDir("/tmp/runner/_diag")
	for _, f := range files {
		fmt.Println(f.Name())
		content, _ := ioutil.ReadFile("/tmp/runner/_diag/" + f.Name())
		fmt.Println(string(content))
	}
	fmt.Println("Done reading logs...")
}

// copy copies the source to destination directories recursively
func copy(source, destination string) error {
	var err error = filepath.Walk(source, func(path string, info os.FileInfo, err error) error {
		var relPath string = strings.Replace(path, source, "", 1)
		if relPath == "" {
			return nil
		}
		if info.IsDir() {
			return os.Mkdir(filepath.Join(destination, relPath), 0755)
		}

		var data, err1 = ioutil.ReadFile(filepath.Join(source, relPath))
		if err1 != nil {
			return err1
		}
		return ioutil.WriteFile(filepath.Join(destination, relPath), data, 0777)
	})
	return err
}

func main() {
	lambda.Start(HandleRequest)
}
