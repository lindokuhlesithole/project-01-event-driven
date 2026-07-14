terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-471147325238"
    key            = "event-driven-orders/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "event-driven-orders"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Lambda execution role
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Separate IAM policies (more reliable than inline)
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:UpdateItem"
      ]
      Resource = [
        aws_dynamodb_table.inventory.arn,
        aws_dynamodb_table.payments.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy" "lambda_eventbridge" {
  name = "lambda-eventbridge-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.order_bus.arn
    }]
  })
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name = "lambda-sqs-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      Resource = [
        aws_sqs_queue.inventory_dlq.arn,
        aws_sqs_queue.payment_dlq.arn,
        aws_sqs_queue.notification_dlq.arn
      ]
    }]
  })
}

# Wait for IAM propagation (critical fix)
resource "time_sleep" "wait_for_iam" {
  depends_on = [
    aws_iam_role_policy.lambda_dynamodb,
    aws_iam_role_policy.lambda_eventbridge,
    aws_iam_role_policy.lambda_sqs,
    aws_iam_role_policy_attachment.lambda_basic
  ]
  create_duration = "15s"
}

# Lambda zip archives
data "archive_file" "producer" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/../build/producer.zip"
  excludes    = ["consumers/*", "shared/__pycache__/*", "producer/__pycache__/*"]
}

data "archive_file" "consumers" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/../build/consumers.zip"
  excludes    = ["producer/*", "shared/__pycache__/*", "consumers/__pycache__/*"]
}

# EventBridge Bus
resource "aws_cloudwatch_event_bus" "order_bus" {
  name = "orders-event-bus"
}

resource "aws_cloudwatch_event_archive" "order_archive" {
  name             = "orders-archive"
  event_source_arn = aws_cloudwatch_event_bus.order_bus.arn
  retention_days   = 30

  event_pattern = jsonencode({
    account = [data.aws_caller_identity.current.account_id]
  })
}

# DynamoDB Tables
resource "aws_dynamodb_table" "inventory" {
  name           = "inventory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  range_key      = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "inventory"
  }
}

resource "aws_dynamodb_table" "payments" {
  name           = "payments"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  range_key      = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "payments"
  }
}

# SQS Dead Letter Queues
resource "aws_sqs_queue" "inventory_dlq" {
  name = "inventory-dlq"
}

resource "aws_sqs_queue" "payment_dlq" {
  name = "payment-dlq"
}

resource "aws_sqs_queue" "notification_dlq" {
  name = "notification-dlq"
}

# Lambda Functions — ALL depend on time_sleep to ensure IAM is ready
resource "aws_lambda_function" "producer" {
  function_name    = "order-producer"
  runtime          = "python3.11"
  handler          = "producer.handler.lambda_handler"
  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 10
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.order_bus.name
    }
  }

  depends_on = [time_sleep.wait_for_iam]
}

resource "aws_lambda_function" "inventory" {
  function_name    = "inventory-service"
  runtime          = "python3.11"
  handler          = "consumers.inventory_handler.lambda_handler"
  filename         = data.archive_file.consumers.output_path
  source_code_hash = data.archive_file.consumers.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 10
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.inventory_dlq.arn
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory.name
    }
  }

  depends_on = [time_sleep.wait_for_iam]
}

resource "aws_lambda_function" "payment" {
  function_name    = "payment-service"
  runtime          = "python3.11"
  handler          = "consumers.payment_handler.lambda_handler"
  filename         = data.archive_file.consumers.output_path
  source_code_hash = data.archive_file.consumers.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 10
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.payment_dlq.arn
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.payments.name
    }
  }

  depends_on = [time_sleep.wait_for_iam]
}

resource "aws_lambda_function" "notification" {
  function_name    = "notification-service"
  runtime          = "python3.11"
  handler          = "consumers.notification_handler.lambda_handler"
  filename         = data.archive_file.consumers.output_path
  source_code_hash = data.archive_file.consumers.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 10
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.notification_dlq.arn
  }

  depends_on = [time_sleep.wait_for_iam]
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "inventory" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inventory_rule.arn
}

resource "aws_lambda_permission" "payment" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payment.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.payment_rule.arn
}

resource "aws_lambda_permission" "notification" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.notification_rule.arn
}

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "inventory_rule" {
  name           = "inventory-rule"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name

  event_pattern = jsonencode({
    source      = ["order.service"]
    detail-type = ["OrderPlaced"]
  })
}

resource "aws_cloudwatch_event_target" "inventory" {
  rule           = aws_cloudwatch_event_rule.inventory_rule.name
  arn            = aws_lambda_function.inventory.arn
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
}

resource "aws_cloudwatch_event_rule" "payment_rule" {
  name           = "payment-rule"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name

  event_pattern = jsonencode({
    source      = ["order.service"]
    detail-type = ["OrderPlaced"]
  })
}

resource "aws_cloudwatch_event_target" "payment" {
  rule           = aws_cloudwatch_event_rule.payment_rule.name
  arn            = aws_lambda_function.payment.arn
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
}

resource "aws_cloudwatch_event_rule" "notification_rule" {
  name           = "notification-rule"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name

  event_pattern = jsonencode({
    source      = ["order.service"]
    detail-type = ["OrderPlaced"]
  })
}

resource "aws_cloudwatch_event_target" "notification" {
  rule           = aws_cloudwatch_event_rule.notification_rule.name
  arn            = aws_lambda_function.notification.arn
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
}

# API Gateway
resource "aws_api_gateway_rest_api" "orders" {
  name        = "EventDrivenOrdersApi"
  description = "API for order processing"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.producer.invoke_arn
}

resource "aws_api_gateway_method_response" "post_202" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = "202"
}

resource "aws_api_gateway_integration_response" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = aws_api_gateway_method_response.post_202.status_code

  depends_on = [aws_api_gateway_integration.lambda]
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.orders.id

  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration_response.lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  stage_name    = "v1"
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "orders" {
  dashboard_name = "EventDrivenOrders"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Orders Received"
          region = var.aws_region
          metrics = [[
            "AWS/ApiGateway", "Count",
            "ApiName", aws_api_gateway_rest_api.orders.name,
            { stat = "Sum", period = 60 }
          ]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          metrics = [[
            "AWS/Lambda", "Errors",
            { stat = "Sum", period = 60 }
          ]]
        }
      }
    ]
  })
}
