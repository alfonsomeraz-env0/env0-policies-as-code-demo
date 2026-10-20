# env zero Policies as Code Demo

Guardrails written as code, reviewed in PRs, unit tested, and enforced by env zero on every deploy. A plan that opens PostgreSQL to the internet is denied before apply, whether a person, a pipeline or an AI agent proposed it.

## Try it in two minutes (no accounts)

You need [`opa`](https://www.openpolicyagent.org/docs/latest/#running-opa) and `jq`.

```bash
brew install opa jq                      # or use your package manager
git clone https://github.com/alfonsomeraz-env0/env0-policies-as-code-demo
cd env0-policies-as-code-demo
make test                                # 58 unit tests
scripts/run-examples.sh                  # every sample plan, outcome checked
COST_DIFF=5 COST_TOTAL=20 scripts/eval-plan.sh baseline examples/plans/03-open-database.json
```

The last command prints:

```json
{
  "deny": [
    "[baseline/network] aws_vpc_security_group_ingress_rule.postgres exposes port 5432 to 0.0.0.0/0 (only ports 80, 443 may face the internet)"
  ],
  "pending": [],
  "warn": [],
  "allow": []
}
```

Change `cidr_ipv4` in `examples/plans/03-open-database.json` to `10.0.0.0/16` and run it again: it passes.

## What's in the repo

```
policies/
  baseline/      assigned to the parent project, inherited by dev and prod
  production/    assigned to prod only (change control)
tests/           Rego unit tests, one folder per policy
examples/plans/  sample plans, runnable with only opa and jq
app/             demo infrastructure with a variable per policy rule
  scenarios/     one .tfvars per outcome
  policy_data.json
control-plane/   env0 Terraform provider: projects, policies, assignments, template, budget
scripts/         local plan -> policy evaluation
```

- **Approval policies** (OPA / Rego) decide per deployment: `deny`, `pending`, `warn` or `allow`.
- **Policy data** (`policy_data.json`) lets allowlists and thresholds change without editing Rego.
- **Control plane as code**: projects, policy assignments, project policies and budget are Terraform.
- **Policy CI**: `opa fmt`, `opa check`, `opa test` and the example plans run on every PR.

## What the policies enforce

| Policy | Rule | Result |
|---|---|---|
| baseline | Public S3 ACL, or public access block disabled | deny |
| baseline | Any port other than 80 / 443 open to `0.0.0.0/0` or `::/0` (SSH, RDP, databases, all-traffic) | deny |
| baseline | Missing `Owner`, `CostCenter`, `Environment` tags | deny |
| baseline | Instance type outside the allowlist, no IMDSv2, unencrypted root volume | deny |
| baseline | Cost diff above `warn_diff` / `pending_diff`, total above `deny_total` | warn / pending / deny |
| production | Change freeze flag set | deny |
| production | Requester is the only approver | deny |
| production | Delete or replace; IAM / KMS change; security group rule edit; non-`cd` trigger | pending |
| production | Routine `cd` change | allow |

Strictest result wins: `deny` > `pending` > `warn` > `allow`. env zero holds for approval when no rule fires, so each policy says `allow` explicitly for its clean path.

## Run it in env zero

> **Cost and safety:** the scenarios deploy real AWS resources (EC2 instances and S3 buckets) in your account.
> - Assign the policies before you deploy scenarios `02` to `07`. Without them, `02-public-bucket` creates a genuinely public S3 bucket.
> - Set a TTL (`--ttl 24h`) or destroy each environment when you finish.

1. **Use this repo as is** (it is public, so env zero needs no VCS connection), or **fork it** to change the policies and point `repo_url` at your fork.
2. **Create the env zero objects:**

   ```bash
   cd control-plane
   cp terraform.tfvars.example terraform.tfvars   # defaults to this repo; add vcs_connection_id for a private fork
   export ENV0_API_KEY=... ENV0_API_SECRET=... ENV0_ORGANIZATION_ID=...
   terraform init && terraform apply
   ```

   Set `parent_project_id` to nest the demo under an existing project.
3. **Give each project AWS credentials** in env zero (or pass `cloud_credentials_id`).
4. **Create an environment** from the `pac-demo-app` template in `pac-demo-dev`, and another in `pac-demo-prod`.

### Demo script

Set the scenario's variables on the environment (Terraform variables) and deploy. Files are in `app/scenarios/`.

| Scenario | Dev | Prod |
|---|---|---|
| `01-clean` | allow | allow on a `cd` trigger, **pending** on a manual deploy |
| `02-public-bucket` | deny | deny |
| `03-open-database` | deny | deny |
| `04-open-ssh` | deny | deny |
| `05-missing-tags` | deny | deny |
| `06-bad-instance-type` | deny | deny |
| `07-insecure-compute` | deny | deny |
| `08-cost-warn` | warn, continues | warn, continues on `cd` |
| `09-cost-pending` | pending | pending |
| `10-prod-delete` (after `01`) | allow | **pending** (`production/destructive`) |

Cost numbers depend on env zero's estimate; tune `cost` in `app/policy_data.json` if a scenario lands on the wrong side.

Good talking points:

- **Same plan, different project, different outcome**: `10-prod-delete` passes in dev and is held in prod.
- **Approve, then resume**: after a human approves, env zero re-evaluates the policy (`deployResume`). The `pending` rules skip that pass; without that, approvals loop.
- **Separation of duties**: approve a prod change as the requester and it is denied on resume.
- **Change freeze**: set `POLICY_CHANGE_FREEZE=true` on the environment (see `app/env0.yaml`) and every prod deploy is denied.
- **Debugging**: `ENV0_PRINT_POLICY_INPUT=true` (set on the template) prints the exact `input` to the deploy log.

## Local loop

```bash
make ci                                  # fmt-check + check + test + examples
scripts/plan-json.sh 03-open-database > /tmp/plan.json      # needs AWS creds
scripts/eval-plan.sh baseline /tmp/plan.json
TRIGGER=user scripts/eval-plan.sh production /tmp/plan.json
COST_DIFF=120 COST_TOTAL=300 scripts/eval-plan.sh baseline /tmp/plan.json
```

## How it fits together

- env zero evaluates approval policies **after plan and cost estimation**, before apply. Tasks and PR plans are not evaluated.
- One policy = one folder of `.rego` files, all in `package env0`. Tests live outside those folders so env zero never loads them.
- `ENV0_POLICY_DATA_PATH=policy_data.json` (set on the template) is a path **relative to the working directory**. `app/env0.yaml` can overwrite it from `POLICY_DATA_URL` so the platform team owns the allowlists instead of the app team.
- Rego uses `import future.keywords.*` so it parses on both old and new OPA. Pin the version env zero uses with `ENV0_OPA_VERSION`; CI tests against `0.46.1` and `latest`.
- Approval policies disable "Approve plan automatically" on the template or project they are assigned to.

## Status

- 58 Rego unit tests pass on OPA 0.46.1 and 1.21.2, and every sample plan returns its expected outcome. `app/` and `control-plane/` pass `terraform validate`.
- Behaviors to confirm in your own org on the first run:
  - baseline (inherited from the parent project) and production both evaluate on prod environments, and `allow` from one does not mask `pending` from the other
  - `input.approvers` is populated on the resume pass (the self-approval deny depends on it)
  - `costEstimation` fields arrive as expected (the policy accepts numbers or numeric strings)
  - `vcs_connection_id` works on `env0_approval_policy` for your VCS

## Not covered here

Third-party scanners (Checkov, Trivy) as custom flows, PR-label-driven approvals, drift detection and the audit trail. Org-wide TTL policy (`env0_organization_policy`) is left out so the demo cannot change tenant-wide settings.

## License

[MIT](LICENSE)
