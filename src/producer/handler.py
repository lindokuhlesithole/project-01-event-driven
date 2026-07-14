import json
import os
import uuid
import boto3

eventbridge = boto3.client("events")
EVENT_BUS_NAME = os.environ["EVENT_BUS_NAME"]

def lambda_handler(event, context):
    body = json.loads(event["body"])
    order_id = f"order-{uuid.uuid4()}"

    order_event = {
        "Source": "order.service",
        "DetailType": "OrderPlaced",
        "Detail": json.dumps({
            "orderId": order_id,
            "customerId": body.get("customerId"),
            "items": body.get("items", []),
            "shippingAddress": body.get("shippingAddress"),
            "timestamp": body.get("timestamp")
        }),
        "EventBusName": EVENT_BUS_NAME
    }

    eventbridge.put_events(Entries=[order_event])

    return {
        "statusCode": 202,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"orderId": order_id, "status": "ACCEPTED"})
    }
