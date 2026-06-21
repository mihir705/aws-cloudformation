# CloudFormation Conventions

Reusable, composable modules with explicit feature toggles, consistent tagging, and production-safe defaults.

## Core concepts

| Concept | Implementation |
|---------|----------------|
| Module | Nested stack (`AWS::CloudFormation::Stack`) |
| Input | `Parameters` |
| Output | `Outputs` (+ optional `Export`) |
| Derived values | `Mappings` + `Conditions` |
| Optional resources | `Create*` parameter + `Condition` |
| Tags | `Environment`, `Project`, `Owner` parameters |
| Environment config | `parameters/{env}.json` |
| Cross-stack references | `Export`/`ImportValue` or SSM Parameter Store |
| Template versioning | S3 template URL + pinned version in deploy script |

## Naming

- Resource names: `{Name}-{resource-type}` via `!Sub`
- Stack names: `{project}-{environment}-{layer}` (e.g. `myapp-prod-network`)
- Exports: `{Project}-{Environment}-{OutputName}`

## Tagging (required on all resources)

Every module accepts:

| Parameter | Tag key | Example |
|-----------|---------|---------|
| `Environment` | `Environment` | `prod` |
| `Project` | `Project` | `myapp` |
| `Owner` | `Owner` | `platform-team` |

Additional tags: `ManagedBy: CloudFormation`, `Module: {module-name}`

## Module design rules

1. **Feature toggles** — Use `Create*` boolean parameters with `Conditions` for optional resources.
2. **Safe defaults** — Encryption on, public access blocked, deletion protection in prod, Multi-AZ where applicable.
3. **No hardcoded secrets** — Use `AWS::SecretsManager::Secret`, SSM SecureString, or RDS managed master password.
4. **Outputs** — Export IDs needed by downstream stacks; document in module README section.
5. **Interface metadata** — Group parameters in `AWS::CloudFormation::Interface` for console UX.
6. **Version pinning** — Upload templates to S3 with versioned prefixes; never deploy unversioned local paths in prod.

## Stack layering

Deploy in order (each layer exports values consumed by the next):

```
network  →  data  →  application
  VPC         RDS       ECS + ALB
  Subnets     S3        Lambda
  NAT/SG
```

## Environment parameters

Use separate JSON parameter files under `parameters/`:

- `dev.json` — minimal resources, single NAT, smaller instance sizes
- `staging.json` — production-like topology, reduced scale
- `prod.json` — Multi-AZ, deletion protection, longer retention

## Validation

Before deploy:

```powershell
aws cloudformation validate-template --template-body file://cloudformation/modules/vpc/template.yaml
cfn-lint cloudformation/modules/vpc/template.yaml   # optional, recommended
```
