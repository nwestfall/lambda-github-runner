resource "null_resource" "lambda_github_runner_pull_image" {
    provisioner "local-exec" {
        command = "aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${var.runner_repo_uri} && docker pull ${var.runner_image_uri}"
    }
}

resource "null_resource" "lambda_github_runner_tag_image" {
    depends_on = [ null_resource.lambda_github_runner_pull_image ]
    provisioner "local-exec" {
        command = "docker tag ${var.runner_image_uri} ${var.local_runner_repo_uri}:latest"
    }
}

resource "null_resource" "lambda_github_runner_push_image" {
    depends_on = [ null_resource.lambda_github_runner_tag_image ]
    provisioner "local-exec" {
        command = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${var.local_runner_repo_uri} && docker push ${var.local_runner_repo_uri}:latest"
    }
}