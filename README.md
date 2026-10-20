# env0 Policies as Code Demo

Guardrails written as code, reviewed in PRs, unit tested, and enforced by env0 on every deploy.

- **Approval policies** (OPA / Rego) decide per deployment: `deny`, `pending`, `warn` or `allow`.
- **Policy data** (`policy_data.json`) lets allowlists and thresholds change without editing Rego.
- **Control plane as code**: projects, policy assignments, project policies and budget are Terraform (`env0` provider).
- **Policy CI**: `opa fmt`, `opa check`, `opa test` on every PR.

```
policies/
  baseline/      assigned to the parent project, inherited by dev and prod
  production/    assigned to prod only (change control)
tests/           Rego unit tests, one folder per policy
app/             demo infrastructure with a variable per policy rule
  scenarios/     one .tfvars per outcome
  policy_data.json
control-plane/   env0 provider: projects, policies, assignments, template, budget
scripts/         local plan -> policy evaluation
```

## What the policies enforce

| Policy | Rule | Result |
|---|---|---|
| baseline | Public S3 ACL, or public access block disabled | deny |
| baseline | SSH / RDP open to `0.0.0.0/0` or `::/0` (HTTPS is fine) | deny |
| baseline | Missing `Owner`, `CostCenter`, `Environment` tags | deny |
| baseline | Instance type outside the allowlist, no IMDSv2, unencrypted root volume | deny |
| baseline | Cost diff above `warn_diff` / `pending_diff`, total above `deny_total` | warn / pending / deny |
| production | Change freeze flag set | deny |
| production | Requester is the only approver | deny |
| production | Delete or replace; IAM / KMS change; security group rule edit; non-`cd` trigger | pending |
| production | Routine `cd` change | allow |

Strictest result wins: `deny` > `pending` > `warn` > `allow`. env0 holds for approval when no rule fires, so each policy says `allow` explicitly for its clean path.

## Setup

1. **Push this folder as its own Git repo** that env0 can read.
2. **Create the env0 objects:**

   ```bash
   cd control-plane
   cp terraform.tfvars.example terraform.tfvars   # set repo_url (and vcs_connection_id if private)
   export ENV0_API_KEY=... ENV0_API_SECRET=... ENV0_ORGANIZATION_ID=...
   terraform init && terraform apply
   ```

3. **Give each project AWS credentials** in env0 (or pass `cloud_credentials_id`).
4. **Create an environment** from the `pac-demo-app` template in `pac-demo-dev`, and another in `pac-demo-prod`.

## Demo script

Set the scenario's variables on the environment (Terraform variables) and deploy. Files are in `app/scenarios/`.

| Scenario | Dev | Prod |
|---|---|---|
| `01-clean` | allow | allow on a `cd` trigger, **pending** on a manual deploy |
| `02-public-bucket` | deny | deny |
| `03-open-ssh` | deny | deny |
| `04-missing-tags` | deny | deny |
| `05-bad-instance-type` | deny | deny |
| `06-insecure-compute` | deny | deny |
| `07-cost-warn` | warn, continues | warn, continues on `cd` |
| `08-cost-pending` | pending | pending |
| `09-prod-delete` (after `01`) | allow | **pending** (`production/destructive`) |

Cost numbers depend on env0's estimate; tune `cost` in `app/policy_data.json` if a scenario lands on the wrong side.

Good talking points:

- **Same plan, different project, different outcome**: `09-prod-delete` passes in dev and is held in prod.
- **Approve, then resume**: after a human approves, env0 re-evaluates the policy (`deployResume`). The `pending` rules skip that pass; without that, approvals loop.
- **Separation of duties**: approve a prod change as the requester and it is denied on resume.
- **Change freeze**: set `POLICY_CHANGE_FREEZE=true` on the environment (see `app/env0.yaml`) and every prod deploy is denied.
- **Debugging**: `ENV0_PRINT_POLICY_INPUT=true` (set on the template) prints the exact `input` to the deploy log.

## Local loop

```bash
make ci                                  # fmt-check + check + test
scripts/plan-json.sh 02-public-bucket > /tmp/plan.json      # needs AWS creds
scripts/eval-plan.sh baseline /tmp/plan.json
TRIGGER=user scripts/eval-plan.sh production /tmp/plan.json
COST_DIFF=120 COST_TOTAL=300 scripts/eval-plan.sh baseline /tmp/plan.json
```

## How it fits together

- env0 evaluates approval policies **after plan and cost estimation**, before apply. Tasks and PR plans are not evaluated.
- One policy = one folder of `.rego` files, all in `package env0`. Tests live outside those folders so env0 never loads them.
- `ENV0_POLICY_DATA_PATH=policy_data.json` (set on the template) is a path **relative to the working directory**. `app/env0.yaml` can overwrite it from `POLICY_DATA_URL` so the platform team owns the allowlists instead of the app team.
- Rego uses `import future.keywords.*` so it parses on both old and new OPA. Pin env0's version with `ENV0_OPA_VERSION`; CI tests against `0.46.1` and `latest`.
- Approval policies disable "Approve plan automatically" on the template or project they are assigned to.

## Status

- 50 Rego unit tests pass on OPA 0.46.1 and 1.21.2. `app/` and `control-plane/` pass `terraform validate`.
- **Not yet run against a live env0 org.** Confirm on first deploy:
  - baseline (inherited from the parent project) and production both evaluate on prod environments, and `allow` from one does not mask `pending` from the other
  - `input.approvers` is populated on the resume pass (the self-approval deny depends on it)
  - `costEstimation` fields arrive as expected (the policy accepts numbers or numeric strings)
  - `vcs_connection_id` works on `env0_approval_policy` for your VCS

## Not covered here

- Third-party scanners (Checkov, Trivy) as custom flows: see `custom-flows/` in `env0-demos`.
- PR-label-driven approvals: see `pr-label-approval-policy/` in `env0-demos`.
- Org-wide TTL policy (`env0_organization_policy`), left out so the demo cannot change tenant-wide settings.
