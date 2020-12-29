terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}

variable "aws_region" {
    description = "AWS Region to deploy in"
    default = "us-east-1"
}

variable "github_token" {
    description = "Github PAT token with REPO access"
    sensitive = true
}

variable "github_secret" {
    description = "Github Webhook Secret to validate payload signature"
    sensitive = true
}

variable "sqs_name" {
    description = "Name of the SQS queue for the lambda runner."
    default = "lambda-github-runner-queue"
}

variable "api_gateway_name" {
    description = "Name of the API Gateway for the lambda webhook."
    default = "lambda-github-webook"
}

variable "webhook_lambda_name" {
    description = "Name of the lambda function for the github webhook."
    default = "lambda-github-webhook"
}

variable "runner_lambda_name" {
    description = "Name of the lambda function for the github action runner."
    default = "lambda-github-runner"
}

variable "runner_repo_uri" {
    description = "Repo URI to use for Lambda Runner (only if you want a custom version)"
    default = "public.ecr.aws/n9q0k4a8"
}

variable "runner_image_uri" {
    description = "Image URI to use for Lambda Runner (only change if you want a custom version)"
    default = "public.ecr.aws/n9q0k4a8/lambda-github-runner:latest"
}

variable "runner_timeout" {
    description = "Timeout of Github Runner in seconds"
    default = 900
    type = number
    validation {
        condition     = var.runner_timeout > 0 && var.runner_timeout < 901
        error_message = "Runner timeout must be in-between 1 and 900."
    }
}

variable "runner_memory" {
    description = "Memory configuration for the Github runner"
    default = 2048
    type = number
    validation {
        condition     = var.runner_memory >= 128 && var.runner_memory <= 10240 && var.runner_memory % 128 == 0
        error_message = "Runner memory must be in-between 128 and 10240, and in increments of 128."
    }
}

variable "cloudwatch_retention_days" {
    description = "Number of days to keep cloudwatch logs."
    default = 14
    type = number
    validation { 
        condition     = var.cloudwatch_retention_days > 0
        error_message = "Cloudwatch retention days must be greater then 0."
    }
}

provider "aws" {
    region = var.aws_region
}

resource "aws_iam_policy" "lambda_runner_logging" {
    name        = "${var.runner_lambda_name}_logging"
    path        = "/"
    description = "IAM policy for logging from ${var.runner_lambda_name}"

    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.runner_lambda_name}:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_webhook_logging" {
    name        = "${var.webhook_lambda_name}_logging"
    path        = "/"
    description = "IAM policy for logging from ${var.webhook_lambda_name}"

    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.webhook_lambda_name}:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role" "cloudwatch" {
    name = "api_gateway_cloudwatch_global"

    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
    name = "default"
    role = aws_iam_role.cloudwatch.id

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "lambda_github_runner_role" {
    path = "/service-role/"
    name = "lambda-github-runner-role-hjt0uhf1"
    assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    max_session_duration = 3600
}

resource "aws_iam_role" "lambda_github_webhook_role" {
    path = "/service-role/"
    name = "lambda-github-webhook-role-gzxhup3h"
    assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    max_session_duration = 3600
}

resource "aws_sqs_queue" "lambda_github_sqs" {
    delay_seconds = "0"
    max_message_size = "262144"
    message_retention_seconds = "900"
    receive_wait_time_seconds = "20"
    visibility_timeout_seconds = "25"
    name = var.sqs_name
}

resource "aws_sqs_queue_policy" "lambda_github_sqs_policy" {
    policy = "{\"Version\":\"2008-10-17\",\"Id\":\"__default_policy_ID\",\"Statement\":[{\"Sid\":\"__owner_statement\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::034828384224:root\"},\"Action\":\"SQS:*\",\"Resource\":\"${aws_sqs_queue.lambda_github_sqs.arn}\"}]}"
    queue_url = "https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.sqs_name}"
}

resource "aws_ecr_repository" "lambda_github_runner_repo" {
    name = "lambda-github-runner"
}

resource "aws_iam_policy" "lambda_github_runner_read_sqs" {
    name        = "lambda_github_runner_read_sqs"
    path        = "/"
    description = "IAM policy for reading the SQS queue for lambda-github-runner"

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "sqs:ReceiveMessage"
            ],
            "Resource": "${aws_sqs_queue.lambda_github_sqs.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "lambda_github_webhook_write_sqs" {
    name        = "lambda_github_webhook_write_sqs"
    path        = "/"
    description = "IAM policy for write to the SQS queue for lambda-github-runner"

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "sqs:SendMessage",
            "Resource": "${aws_sqs_queue.lambda_github_sqs.arn}"
        }
    ]
}
EOF
}

module "lambda_runner_push" {
    source = "./runner_module"

    aws_region = var.aws_region
    local_runner_repo_uri = aws_ecr_repository.lambda_github_runner_repo.repository_url
    runner_repo_uri = var.runner_repo_uri
    runner_image_uri = var.runner_image_uri
}

resource "aws_cloudwatch_log_group" "lambda_github_runner_cloudwatch" {
  name              = "/aws/lambda/${var.runner_lambda_name}"
  retention_in_days = var.cloudwatch_retention_days
}

resource "aws_iam_role_policy_attachment" "lambda_github_runner_logs" {
  role       = aws_iam_role.lambda_github_runner_role.name
  policy_arn = aws_iam_policy.lambda_runner_logging.arn
}

resource "aws_iam_role_policy_attachment" "lambda_github_runner_read_sqs" {
  role       = aws_iam_role.lambda_github_runner_role.name
  policy_arn = aws_iam_policy.lambda_github_runner_read_sqs.arn
}

resource "aws_lambda_function" "lambda_github_runner_lambda" {
    depends_on = [ module.lambda_runner_push ]
    description = "Github Action Runner"
    function_name = var.runner_lambda_name
    memory_size = var.runner_memory
    role = aws_iam_role.lambda_github_runner_role.arn
    timeout = var.runner_timeout
    package_type = "Image"
    image_uri = "${aws_ecr_repository.lambda_github_runner_repo.repository_url}:latest"
    tracing_config {
        mode = "PassThrough"
    }
}

resource "aws_iam_policy" "lambda_github_runner_invoke" {
    name        = "${var.runner_lambda_name}_invoke"
    path        = "/"
    description = "IAM policy for invoking ${var.runner_lambda_name}"

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "${aws_lambda_function.lambda_github_runner_lambda.arn}"
        }
    ]
}
EOF
}

resource "aws_cloudwatch_log_group" "lambda_github_webhook_cloudwatch" {
  name              = "/aws/lambda/${var.webhook_lambda_name}"
  retention_in_days = var.cloudwatch_retention_days
}

resource "aws_iam_role_policy_attachment" "lambda_github_webhook_logs" {
  role       = aws_iam_role.lambda_github_webhook_role.name
  policy_arn = aws_iam_policy.lambda_webhook_logging.arn
}

resource "aws_iam_role_policy_attachment" "lambda_github_webhook_invoke_runner" {
  role       = aws_iam_role.lambda_github_webhook_role.name
  policy_arn = aws_iam_policy.lambda_github_runner_invoke.arn
}

resource "aws_iam_role_policy_attachment" "lambda_github_webhook_write_sqs" {
  role       = aws_iam_role.lambda_github_webhook_role.name
  policy_arn = aws_iam_policy.lambda_github_webhook_write_sqs.arn
}

module "lambda_webhook_pull" {
    source = "./webhook_module"
}

resource "aws_lambda_function" "lambda_github_webhook_lambda" {
    depends_on = [ module.lambda_webhook_pull ]

    description = "Github Webhook Lambda"
    environment {
        variables = {
            SQS_QUEUE_URL = "https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.sqs_name}"
            GITHUB_TOKEN = var.github_token
        }
    }
    function_name = var.webhook_lambda_name
    handler = "main"
    filename = module.lambda_webhook_pull.file_location
    #source_code_hash = filebase64sha256(module.lambda_webhook_pull.file_location)
    memory_size = 128
    role = aws_iam_role.lambda_github_webhook_role.arn
    runtime = "go1.x"
    timeout = 10
    tracing_config {
        mode = "PassThrough"
    }
}

resource "aws_api_gateway_account" "lambda_github_webhook_account" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_api_gateway_rest_api" "lambda_github_webhook_rest_api" {
    name = var.api_gateway_name
    description = "Webhook API for Lambda Github Runner"
    api_key_source = "HEADER"
    endpoint_configuration {
        types = [
            "EDGE"
        ]
    }
}

resource "aws_api_gateway_method" "lambda_github_webhook_method" {
    rest_api_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
    resource_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.root_resource_id
    http_method = "ANY"
    authorization = "NONE"
    api_key_required = false
}

resource "aws_api_gateway_integration" "lambda_github_webhook_integration" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
  resource_id             = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.root_resource_id
  http_method             = aws_api_gateway_method.lambda_github_webhook_method.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_github_webhook_lambda.invoke_arn
}

resource "aws_api_gateway_resource" "lambda_github_webhook_resource" {
    rest_api_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
    path_part = "{proxy+}"
    parent_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.root_resource_id
}

resource "aws_api_gateway_method" "lambda_github_webhook_proxy_method" {
    rest_api_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
    resource_id = aws_api_gateway_resource.lambda_github_webhook_resource.id
    http_method = "ANY"
    authorization = "NONE"
    api_key_required = false
    request_parameters = {
        "method.request.path.proxy" = true
    }
}

resource "aws_api_gateway_integration" "lambda_github_webhook_integration2" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
  resource_id             = aws_api_gateway_resource.lambda_github_webhook_resource.id
  http_method             = aws_api_gateway_method.lambda_github_webhook_proxy_method.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_github_webhook_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "lambda_github_webhook_deployment" {
    depends_on = [aws_api_gateway_integration.lambda_github_webhook_integration, aws_api_gateway_integration.lambda_github_webhook_integration2]
    rest_api_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
    stage_name  = "staging"
}

resource "aws_api_gateway_stage" "lambda_github_webhook_stage" {
  depends_on = [aws_cloudwatch_log_group.lambda_github_webhook_rest_api_cloudwatch, aws_api_gateway_account.lambda_github_webhook_account]

  stage_name = "default"
  rest_api_id = aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id
  deployment_id = aws_api_gateway_deployment.lambda_github_webhook_deployment.id
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda_github_webhook_rest_api_cloudwatch.arn
    format = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }
}

resource "aws_cloudwatch_log_group" "lambda_github_webhook_rest_api_cloudwatch" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id}/default"
  retention_in_days = var.cloudwatch_retention_days
}

resource "aws_lambda_permission" "lambda_github_webhook_lambda_permission" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_github_webhook_lambda.arn
    principal = "apigateway.amazonaws.com"
    source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id}/*/${aws_api_gateway_method.lambda_github_webhook_method.http_method}/"
}

resource "aws_lambda_permission" "lambda_github_webhook_lambda_permission2" {
    statement_id  = "AllowExecutionFromAPIGateway2"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_github_webhook_lambda.arn
    principal = "apigateway.amazonaws.com"
    source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.lambda_github_webhook_rest_api.id}/*/${aws_api_gateway_method.lambda_github_webhook_proxy_method.http_method}${aws_api_gateway_resource.lambda_github_webhook_resource.path}"
}

output "github_webhook_url" {
    value = aws_api_gateway_stage.lambda_github_webhook_stage.invoke_url
}