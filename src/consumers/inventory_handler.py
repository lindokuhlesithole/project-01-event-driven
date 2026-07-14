import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

def lambda_handler(event, context):
    detail = event.get("detail", {})
    order_id = detail.get("orderId")

    for item in detail.get("items", []):
        table.put_item(Item={
            "pk": f"ORDER#{order_id}",
            "sk": f"ITEM#{item['sku']}",
            "quantity": item["quantity"],
            "status": "RESERVED",
            "type": "INVENTORY"
        })

    return {"statusCode": 200}
