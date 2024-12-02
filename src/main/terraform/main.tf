output "module_path" {
  value = "${path.module}"
}

locals {
  lambda_zip_path = "${path.module}/../../../target/daisy-1.0-SNAPSHOT.jar"
}

provider "aws" {
  profile = "xeo"
  region  = "us-west-2"
}

# DynamoDB Table
resource "aws_dynamodb_table" "daisy" {
  name           = "daisy-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  stream_enabled = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "id"
    type = "S"
  }
}

# Kinesis Data Stream
resource "aws_kinesis_stream" "daisy" {
  name             = "daisy-stream"
  shard_count      = 1
  retention_period = 24
}

# OpenSearch Domain
resource "aws_opensearch_domain" "daisy" {
  domain_name    = "daisy-domain"
  engine_version = "OpenSearch_1.0"

  cluster_config {
    instance_type  = "t2.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach Basic Execution Policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach DynamoDB Permissions to Lambda Execution Role
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Resource = "arn:aws:dynamodb:us-west-2:437798111733:table/daisy-table"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Lambda Function for API Gateway Integration
resource "aws_lambda_function" "dynamodb_api" {
  function_name    = "dynamodb_api"
  runtime          = "java21"
  handler          = "daisy.ApiGatewayToDynamoDBHandler::handleRequest"
  role             = aws_iam_role.lambda_exec.arn
  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.daisy.name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "dynamodb_api" {
  name        = "DaisyApi"
  description = "API Gateway for DaisyApi"
}

# API Gateway Resource (Endpoint)
resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.dynamodb_api.id
  parent_id   = aws_api_gateway_rest_api.dynamodb_api.root_resource_id
  path_part   = "products"
}

# API Gateway Method for POST
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.dynamodb_api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dynamodb_api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.dynamodb_api.invoke_arn
}

# Deploy the API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.dynamodb_api.id
  stage_name  = "dev"

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# Grant API Gateway Permission to Invoke the Lambda Function
resource "aws_lambda_permission" "apigateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dynamodb_api.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.dynamodb_api.execution_arn}/*/*"
}

# Lambda Function: DynamoDB to Kinesis
resource "aws_lambda_function" "dynamodb_to_kinesis" {
  function_name    = "dynamodb_to_kinesis"
  runtime          = "java21"
  handler          = "DynamoDBToKinesisHandler::handleRequest"
  role             = aws_iam_role.lambda_exec.arn
  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.daisy.name
    }
  }
}

# Event Source Mapping: DynamoDB to Lambda
resource "aws_lambda_event_source_mapping" "dynamodb_to_kinesis" {
  event_source_arn = aws_dynamodb_table.daisy.stream_arn
  function_name    = aws_lambda_function.dynamodb_to_kinesis.arn
  starting_position = "LATEST"
}

# Lambda Function: Kinesis to OpenSearch
resource "aws_lambda_function" "kinesis_to_opensearch" {
  function_name    = "kinesis_to_opensearch"
  runtime          = "java21"
  handler          = "KinesisToOpenSearchHandler::handleRequest"
  role             = aws_iam_role.lambda_exec.arn
  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.daisy.endpoint
    }
  }
}