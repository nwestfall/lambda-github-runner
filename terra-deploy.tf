provider "aws" {
    region = "us-east-1"
}

resource "aws_iam_role" "lambda_github_runner_role" {
    path = "/service-role/"
    name = "lambda-github-runner-role-hjt0uhf1"
    assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    max_session_duration = 3600
    tags {}
}

resource "aws_iam_role" "lambda_github_webhook_role" {
    path = "/service-role/"
    name = "lambda-github-webhook-role-gzxhup3h"
    assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    max_session_duration = 3600
    tags {}
}

resource "aws_sqs_queue" "lambda_github_sqs" {
    delay_seconds = "0"
    max_message_size = "262144"
    message_retention_seconds = "900"
    receive_wait_time_seconds = "20"
    visibility_timeout_seconds = "25"
    name = "lambda-github-runner-queue"
}

resource "aws_sqs_queue_policy" "lambda_github_sqs_policy" {
    policy = "{\"Version\":\"2008-10-17\",\"Id\":\"__default_policy_ID\",\"Statement\":[{\"Sid\":\"__owner_statement\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::034828384224:root\"},\"Action\":\"SQS:*\",\"Resource\":\"${aws_sqs_queue.lambda_github_sqs.arn}\"}]}"
    queue_url = "${aws_sqs_queue.lambda_github_sqs.url}"
}

resource "aws_lambda_function" "lambda_github_webhook_lambda" {
    description = "Github Webhook Lambda"
    environment {
        variables {
            SQS_QUEUE_URL = "${aws_sqs_queue.lambda_github_sqs.url}"
            GITHUB_TOKEN = "746790c80ef55a5a89abf47a80f27649d47efc6f"
        }
    }
    function_name = "lambda-github-webhook"
    handler = "main"
    s3_bucket = "prod-04-2014-tasks"
    s3_key = "/snapshots/034828384224/lambda-github-webhook-987a9440-916a-47a9-9539-4005b7316584"
    s3_object_version = "advowJhKq3m0jjs5_7ShX0j7m5DvIJJH"
    memory_size = 128
    role = "${aws_iam_role.lambda_github_webhook_role.arn}"
    runtime = "go1.x"
    timeout = 10
    tracing_config {
        mode = "PassThrough"
    }
}

resource "aws_lambda_function" "lambda_github_runner_lambda" {
    description = "Github Action Runner"
    function_name = "lambda-github-runner"
    memory_size = 2048
    role = "${aws_iam_role.lambda_github_runner_role.arn}"
    timeout = 900
    tracing_config {
        mode = "PassThrough"
    }
}

resource "aws_lambda_permission" "lambda_github_webhook_lambda_permission_1" {
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.lambda_github_webhook_lambda.arn}"
    principal = "apigateway.amazonaws.com"
    source_arn = "arn:aws:execute-api:us-east-1:034828384224:ck213d3bd4/*/*/*"
}

resource "aws_lambda_permission" "lambda_github_webhook_lambda_permission_2" {
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.lambda_github_webhook_lambda.arn}"
    principal = "apigateway.amazonaws.com"
    source_arn = "arn:aws:execute-api:us-east-1:034828384224:ck213d3bd4/*/*/"
}

resource "aws_ecr_repository" "lambda_github_runner_ecr" {
    name = "lambda-github-runner"
}

resource "aws_api_gateway_rest_api" "ApiGatewayRestApi" {
    name = "lambda-github-webhook"
    description = "Webhook API for Lambda Github Runner"
    api_key_source = "HEADER"
    endpoint_configuration {
        types = [
            "EDGE"
        ]
    }
}

resource "aws_api_gateway_stage" "ApiGatewayStage" {
    stage_name = "default"
    deployment_id = "5s4dyj"
    rest_api_id = "ck213d3bd4"
    cache_cluster_enabled = false
    xray_tracing_enabled = false
}

resource "aws_apigatewayv2_stage" "ApiGatewayV2Stage" {
    name = "default"
    stage_variables {}
    api_id = "furouz6ipl"
    deployment_id = "6pfutx"
    description = "Created by AWS Lambda"
    default_route_settings {
        detailed_metrics_enabled = false
    }
    auto_deploy = true
    Tags {}
}

resource "aws_api_gateway_deployment" "ApiGatewayDeployment" {
    rest_api_id = "ck213d3bd4"
}

resource "aws_api_gateway_deployment" "ApiGatewayDeployment2" {
    rest_api_id = "ck213d3bd4"
}

resource "aws_api_gateway_resource" "ApiGatewayResource" {
    rest_api_id = "ck213d3bd4"
    path_part = "{proxy+}"
    parent_id = "f9h6jz47vg"
}

resource "aws_api_gateway_method" "ApiGatewayMethod" {
    rest_api_id = "ck213d3bd4"
    resource_id = "u2v6q9"
    http_method = "ANY"
    authorization = "NONE"
    api_key_required = false
    request_parameters {
        method.request.path.proxy = true
    }
}

resource "aws_api_gateway_method" "ApiGatewayMethod2" {
    rest_api_id = "ck213d3bd4"
    resource_id = "f9h6jz47vg"
    http_method = "ANY"
    authorization = "NONE"
    api_key_required = false
    request_parameters {}
}

resource "aws_api_gateway_model" "ApiGatewayModel" {
    rest_api_id = "ck213d3bd4"
    name = "Empty"
    description = "This is a default empty schema model"
    schema = <<EOF
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "title" : "Empty Schema",
  "type" : "object"
}
EOF
    content_type = "application/json"
}

resource "aws_api_gateway_model" "ApiGatewayModel2" {
    rest_api_id = "ck213d3bd4"
    name = "Error"
    description = "This is a default error schema model"
    schema = <<EOF
{
  "$schema" : "http://json-schema.org/draft-04/schema#",
  "title" : "Error Schema",
  "type" : "object",
  "properties" : {
    "message" : { "type" : "string" }
  }
}
EOF
    content_type = "application/json"
}
