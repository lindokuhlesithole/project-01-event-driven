# Lessons Learned — Project 01

## 1. IAM Propagation is a Real Problem

**What happened:** Lambda functions failed immediately after creation with `AccessDeniedException` even though IAM policies were defined in the same Terraform file.

**Why:** AWS IAM is eventually consistent. Policies take 10-30 seconds to propagate globally across all regions and services.

**Fix:** Added `time_sleep` resource that waits 15 seconds after all IAM policies are created before creating Lambda functions.

**Takeaway:** Always account for IAM propagation delay in Terraform. CDK/CloudFormation handles this automatically — Terraform does not.

---

## 2. Terraform vs CDK: Different Trade-offs

| Aspect | Terraform | CDK |
|--------|-----------|-----|
| IAM propagation | Manual (`time_sleep`) | Automatic (CloudFormation) |
| Learning curve | HCL syntax | Python/TypeScript |
| Job market | 3x more listings | Growing in AWS-native teams |
| Multi-cloud | Yes | AWS only |
| State control | You own it (S3) | AWS manages it |

**Takeaway:** Both are valid. Terraform gives more control but requires more care. CDK is faster for AWS-only projects.

---

## 3. API Gateway Stage Naming

**What happened:** Old CDK deployment left a `prod` stage behind. Terraform failed to create a new `prod` stage because the name already existed.

**Fix:** Changed stage name to `v1`.

**Takeaway:** Use versioned stage names (`v1`, `v2`) or clean up old deployments before creating new ones.

---

## 4. PowerShell vs Bash for Cloud Testing

**What happened:** `curl` in PowerShell is actually `Invoke-WebRequest` with different syntax. JSON escaping caused errors.

**Fix:** Used `Invoke-RestMethod` with proper PowerShell syntax.

**Takeaway:** Know your shell. Windows PowerShell ≠ Linux Bash. Use the right tool for the environment.

---

## 5. Event-Driven Debugging

**What happened:** When the API returned 500, it was unclear which service failed.

**Fix:** Checked CloudWatch Logs for each Lambda independently. The producer was failing (IAM), but consumers would have been fine.

**Takeaway:** In event-driven architectures, each service has its own logs. Check them all — the failure might not be where you expect.

---

## 6. DynamoDB Single-Table Design

**What we did:** Used `pk` (partition key) and `sk` (sort key) pattern:
- `pk`: `ORDER#<id>`
- `sk`: `ITEM#<sku>` or `PAYMENT`

**Why:** Enables querying all items for an order in a single query.

**Takeaway:** Single-table design is powerful but requires upfront planning of access patterns.

---

## 7. Dead Letter Queues Are Essential

**What we built:** 3 SQS DLQs — one per consumer Lambda.

**Why:** If a consumer fails (e.g., DynamoDB throttling), the event goes to the DLQ instead of being lost.

**Takeaway:** Always add DLQs to async Lambda consumers. They're cheap insurance.

---

## 8. Documentation is Part of the Build

**What we learned:** Writing ADRs, testing results, and lessons learned WHILE building is easier than trying to remember later.

**Takeaway:** Document as you go. Your future self (and interviewers) will thank you.
