resource "null_resource" "lambda_github_webhook_pull_zip" {
    provisioner "local-exec" {
        command = "mkdir -p ${var.file_destination} && aws s3api get-object --bucket lambda-github-webhook --key lambda-github-webhook-function.zip --request-payer true ${var.file_destination}/lambda-github-webhook-function.zip"
    }
}