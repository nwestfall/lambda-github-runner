cd src/lambda-github-webhook
go mod download
GOOS=linux go build -o ../../main
cd ../../
zip function-webhook.zip main

echo "Updating Webhook"
aws lambda update-function-code --function-name lambda-github-webhook --zip-file fileb://function-webhook.zip
echo "Webhook Updated"

rm -rf main
rm -rf function-webhook.zip