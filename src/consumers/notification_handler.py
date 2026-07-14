import json
import os

def lambda_handler(event, context):
    detail = event.get("detail", {})
    order_id = detail.get("orderId")
    customer_id = detail.get("customerId")

    print(f"Sending confirmation for order {order_id} to customer {customer_id}")

    return {"statusCode": 200}
