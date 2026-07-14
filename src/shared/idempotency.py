import boto3
from datetime import datetime, timedelta

class IdempotencyStore:
    def __init__(self, table_name):
        self.table = boto3.resource("dynamodb").Table(table_name)

    def check(self, key):
        try:
            response = self.table.get_item(Key={"pk": f"IDEMP#{key}", "sk": "META"})
            return "Item" in response
        except Exception:
            return False

    def save(self, key, ttl_seconds=3600):
        expires = int((datetime.utcnow() + timedelta(seconds=ttl_seconds)).timestamp())
        self.table.put_item(Item={
            "pk": f"IDEMP#{key}",
            "sk": "META",
            "expires": expires
        })
