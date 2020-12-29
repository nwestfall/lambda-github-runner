cd ../src/lambda-github-webhook
go mod download
GOOS=linux go build -o ../../main
cd ../../
zip lambda-github-webhook-function.zip main

echo "Updating Webhook"
aws s3 cp lambda-github-webhook-function.zip s3://lambda-github-webhook
echo "Webhook Updated"

rm -rf main
rm -rf lambda-github-webhook-function.zip