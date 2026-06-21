# aws-cloudformation

Production-grade AWS CloudFormation templates for layered infrastructure deployment.

## Architecture

Layered stacks with reusable nested modules:

```
cloudformation/
├── modules/          # Reusable nested stack templates
│   ├── vpc/
│   ├── security-group/
│   ├── s3-bucket/
│   ├── iam-role/
│   ├── rds/
│   ├── ecs-cluster/
│   ├── ecs-service/
│   ├── alb/
│   └── lambda/
├── stacks/           # Root stacks
│   ├── network/      # VPC + security groups
│   ├── data/         # RDS + S3
│   └── application/  # ALB + ECS
├── parameters/       # Environment-specific values
└── scripts/
    └── deploy.ps1
```

## Deployment order

```
network  →  data  →  application
```

Each layer exports values via CloudFormation `Export`/`ImportValue` (cross-stack references).

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- An S3 bucket for storing nested stack templates (versioned, private)
- Optional: [cfn-lint](https://github.com/aws-cloudformation/cfn-lint) for local validation

## Quick start

1. Create an S3 bucket for templates:

```powershell
aws s3 mb s3://my-cfn-templates --region us-east-1
aws s3api put-bucket-versioning --bucket my-cfn-templates --versioning-configuration Status=Enabled
```

2. Update parameter files in `cloudformation/parameters/`:
   - Replace `REPLACE_WITH_TEMPLATES_BUCKET` with your bucket name
   - Replace `REPLACE_ACCOUNT_ID` in S3 bucket names
   - Set your AZs, CIDRs, container image, and ACM certificate ARN

3. Deploy all layers:

```powershell
cd cloudformation/scripts
.\deploy.ps1 -Environment dev -TemplateBucket my-cfn-templates -Layer all
```

Deploy a single layer:

```powershell
.\deploy.ps1 -Environment dev -TemplateBucket my-cfn-templates -Layer network
```

## Module feature toggles

Each module uses `Create*` / boolean parameters with CloudFormation `Conditions` to enable or disable optional resources:

| Module | Key toggles |
|--------|-------------|
| VPC | `CreateNatGateway`, `SingleNatGateway`, `OneNatGatewayPerAz`, `EnableFlowLogs` |
| S3 | `EnableVersioning`, `BlockPublicAccess`, `EnableDenyInsecureTransport` |
| RDS | `MultiAz`, `DeletionProtection`, `ManageMasterUserPassword`, `StorageEncrypted` |
| ALB | `EnableHttpsRedirect`, `EnableDeletionProtection` |
| ECS Cluster | `EnableContainerInsights`, `EnableFargateCapacityProviders` |

## Production defaults

- RDS: encryption at rest, Multi-AZ (prod), deletion protection, Secrets Manager master password
- S3: versioning, SSE, public access blocked, deny insecure transport policy
- VPC: flow logs, DNS enabled, database subnet group for RDS
- ALB: TLS 1.3 policy, deletion protection, invalid header dropping
- ECS: deployment circuit breaker with rollback, Container Insights
- Lambda: X-Ray tracing, CloudWatch log retention

## Conventions

See [docs/CONVENTIONS.md](docs/CONVENTIONS.md) for naming, tagging, and module design standards.

## Validate locally

```powershell
aws cloudformation validate-template --template-body file://cloudformation/modules/vpc/template.yaml
cfn-lint cloudformation/modules/**/*.yaml cloudformation/stacks/**/*.yaml
```

## Adding modules

Follow the existing module pattern:

1. `Parameters` with `Environment`, `Project`, `Owner` tags
2. `Conditions` for optional resources
3. `Metadata.AWS::CloudFormation::Interface` for parameter grouping
4. `Outputs` with `Export` for cross-stack references
5. Production-safe defaults (encryption, no public access)

## License

Apache 2.0
