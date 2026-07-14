output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_stage.v1.invoke_url}/orders"
}

output "event_bus_name" {
  description = "EventBridge bus name"
  value       = aws_cloudwatch_event_bus.order_bus.name
}

output "inventory_table_name" {
  description = "Inventory DynamoDB table"
  value       = aws_dynamodb_table.inventory.name
}

output "payments_table_name" {
  description = "Payments DynamoDB table"
  value       = aws_dynamodb_table.payments.name
}
