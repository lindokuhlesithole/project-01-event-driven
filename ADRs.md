# Architecture Decision Records

## ADR 001: Terraform over AWS CDK

**Status:** Accepted  
**Date:** 2026-07-13

### Context
We needed Infrastructure as Code for AWS resources. Two options were evaluated:
1. AWS CDK (Python) — generates CloudFormation
2. Terraform (HCL) — direct AWS API calls

### Decision
Use Terraform.

### Rationale
- **Industry demand:** Terraform appears in ~3x more job listings than CDK
- **Multi-cloud:** Terraform supports AWS, Azure, GCP — transferable skill
- **State management:** S3 backend with DynamoDB locking is production-grade
- **Auditability:** HCL is declarative and easier to review than generated CloudFormation

### Consequences
- Slightly steeper learning curve than CDK's Python syntax
- Manual handling of IAM propagation delays (resolved with `time_sleep`)
- More verbose for simple resources

---

## ADR 002: EventBridge over SNS/SQS

**Status:** Accepted  
**Date:** 2026-07-13

### Context
A single order event needs to be consumed by 3 independent services.

### Decision
Use Amazon EventBridge.

### Rationale
- **Content-based filtering:** Rules can filter events by source, detail-type, or custom fields
- **Schema validation:** Enforces event contracts via JSON Schema
- **Replay capability:** Archive stores events for 30 days
- **Native X-Ray integration:** Distributed tracing out of the box
- **SNS alternative:** Would require 3 separate SQS queues + SNS topic = more moving parts

### Consequences
- ~50ms higher latency than SNS (acceptable for async processing)
- AWS-only service (not portable to other clouds)

---

## ADR 003: Separate DynamoDB Tables per Service

**Status:** Accepted  
**Date:** 2026-07-13

### Context
Each microservice (Inventory, Payment, Notification) needs persistent storage.

### Decision
Use separate DynamoDB tables per service.

### Rationale
- **Blast radius isolation:** A table issue affects only one service
- **Simpler IAM:** One table per role, no cross-service permissions needed
- **Independent scaling:** Each table scales based on its own traffic

### Consequences
- More tables to monitor and manage
- Cannot perform cross-table transactions (by design — services are decoupled)

---

## ADR 004: time_sleep for IAM Propagation

**Status:** Accepted (with caveat)  
**Date:** 2026-07-13

### Context
Terraform creates IAM policies and Lambda functions in parallel. Lambda was failing with `AccessDeniedException` because policies were not yet globally active.

### Decision
Use `time_sleep` resource to pause 15 seconds after IAM policy creation.

### Rationale
- AWS IAM is eventually consistent (10-30 second propagation)
- `depends_on` alone does not guarantee policy readiness
- `time_sleep` is a pragmatic, deterministic workaround

### Consequences
- Adds 15 seconds to every deployment
- Not elegant, but reliable
- **Future improvement:** Use AWS-native retry logic or switch to CloudFormation/CDK for automatic handling
