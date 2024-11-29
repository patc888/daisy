output "module_path" {
  value = "${path.module}"
}
locals {
  lambda_zip_path = "${path.module}/../../../../target/daisy-1.0-SNAPSHOT.jar"
}
provider "aws" {
  profile = "xeo"
  region = "us-west-2"
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
    instance_type = "t2.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }
}

# IAM Role for DynamoDB to Kinesis Lambda
resource "aws_iam_role" "dynamodb_to_kinesis_role" {
  name = "dynamodb_to_kinesis_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "dynamodb_to_kinesis_policy" {
  name = "dynamodb_to_kinesis_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams",
          "kinesis:PutRecord"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_to_kinesis_attach" {
  role       = aws_iam_role.dynamodb_to_kinesis_role.name
  policy_arn = aws_iam_policy.dynamodb_to_kinesis_policy.arn
}


# Lambda Function: DynamoDB to Kinesis
resource "aws_lambda_function" "dynamodb_to_kinesis" {
  function_name    = "dynamodb_to_kinesis"
  runtime          = "java11"
  handler          = "DynamoDBToKinesisHandler::handleRequest"
  role             = aws_iam_role.dynamodb_to_kinesis_role.arn
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

# IAM Role for Kinesis to OpenSearch Lambda
resource "aws_iam_role" "kinesis_to_opensearch_role" {
  name = "kinesis_to_opensearch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "kinesis_to_opensearch_policy" {
  name = "kinesis_to_opensearch_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListStreams",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kinesis_to_opensearch_attach" {
  role       = aws_iam_role.kinesis_to_opensearch_role.name
  policy_arn = aws_iam_policy.kinesis_to_opensearch_policy.arn
}

# Lambda Function: Kinesis to OpenSearch
resource "aws_lambda_function" "kinesis_to_opensearch" {
  function_name    = "kinesis_to_opensearch"
  runtime          = "java11"
  handler          = "KinesisToOpenSearchHandler::handleRequest"
  role             = aws_iam_role.kinesis_to_opensearch_role.arn
  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.daisy.endpoint
    }
  }
}

# Event Source Mapping: Kinesis to Lambda
resource "aws_lambda_event_source_mapping" "kinesis_to_opensearch" {
  event_source_arn = aws_kinesis_stream.daisy.arn
  function_name    = aws_lambda_function.kinesis_to_opensearch.arn
  starting_position = "LATEST"
}