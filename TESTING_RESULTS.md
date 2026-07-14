# Testing Results — Project 01

**Date:** 2026-07-13  
**Tester:** Lindokuhle  
**Environment:** AWS us-east-1, Terraform dev environment

---

## Test 1: API Gateway → Producer Lambda → EventBridge

### Input
```json
{
  "customerId": "cust-12345",
  "items": [
    {"sku": "SKU-001", "quantity": 2, "price": 29.99}
  ],
  "shippingAddress": {
    "city": "Toronto",
    "country": "CA"
  }
}
```

### Expected Result
- HTTP 202 Accepted
- `orderId` generated
- `OrderPlaced` event published to EventBridge

### Actual Result
✅ **PASSED**
```json
{
  "orderId": "order-6709c830-9c4e-4798-89b5b5f4b49",
  "status": "ACCEPTED"
}
```

---

## Test 2: Inventory Consumer → DynamoDB

### Expected Result
- Inventory item reserved in `inventory` table
- `pk` = `ORDER#<orderId>`
- `sk` = `ITEM#SKU-001`
- `status` = `RESERVED`

### Actual Result
✅ **PASSED**
```json
{
  "pk": "ORDER#order-6709c830-9c4e-4798-89b5b5f4b49",
  "sk": "ITEM#SKU-001",
  "quantity": 2,
  "type": "INVENTORY",
  "status": "RESERVED"
}
```

---

## Test 3: Payment Consumer → DynamoDB

### Expected Result
- Payment record created in `payments` table
- `amount` = 59.98 (2 × 29.99)
- `status` = `PROCESSED`

### Actual Result
✅ **PASSED**
```json
{
  "pk": "ORDER#order-6709c830-9c4e-4798-89b5b5f4b49",
  "sk": "PAYMENT",
  "amount": 59.98,
  "status": "PROCESSED",
  "type": "PAYMENT"
}
```

---

## Test 4: Second Order (Different Customer)

### Input
```json
{
  "customerId": "cust-test-2",
  "items": [
    {"sku": "SKU-002", "quantity": 5, "price": 15.50}
  ],
  "shippingAddress": {
    "city": "Johannesburg",
    "country": "ZA"
  }
}
```

### Actual Result
✅ **PASSED**
```json
{
  "orderId": "order-0df1bb67-5ca1-498a-99a4-60e5a232cec",
  "status": "ACCEPTED"
}
```

---

## Test 5: Error Handling — IAM Permission Denied

### Scenario
During initial deployment, Lambda was created before IAM policies propagated.

### Error
```
AccessDeniedException: User is not authorized to perform: events:PutEvents
```

### Resolution
Added `time_sleep` resource to wait 15 seconds after IAM policy creation before creating Lambda functions.

### Result
✅ **FIXED** — All subsequent deployments succeeded.

---

## Summary

| Test | Status |
|------|--------|
| API Endpoint Accepts Orders | ✅ PASS |
| Event Published to EventBridge | ✅ PASS |
| Inventory Consumer Writes to DynamoDB | ✅ PASS |
| Payment Consumer Writes to DynamoDB | ✅ PASS |
| Multiple Orders Processed | ✅ PASS |
| IAM Propagation Race Condition | ✅ FIXED |

**Overall Status: ALL TESTS PASSED**
