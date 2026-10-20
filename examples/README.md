# Sample plans

Trimmed `terraform show -json` output for the app in `../app`, one file per scenario. They let you run the policies with only `opa` and `jq`: no AWS account, no env zero account.

```bash
# one plan through one policy (costs are optional)
COST_DIFF=5 COST_TOTAL=20 ../scripts/eval-plan.sh baseline plans/03-open-database.json

# every plan, with the expected outcome checked
../scripts/run-examples.sh
```

| File | Same as scenario | Baseline result |
|---|---|---|
| `01-clean.json` | `01-clean` | allow |
| `02-public-bucket.json` | `02-public-bucket` | deny |
| `03-open-database.json` | `03-open-database` | deny |
| `04-open-ssh.json` | `04-open-ssh` | deny |
| `05-missing-tags.json` | `05-missing-tags` | deny |
| `06-bad-instance-type.json` | `06-bad-instance-type` | deny |
| `07-insecure-compute.json` | `07-insecure-compute` | deny |
| `10-prod-delete.json` | `10-prod-delete` | allow (the `production` policy holds it) |

Cost scenarios reuse `01-clean.json` with `COST_DIFF` and `COST_TOTAL` set, because cost comes from env zero's estimate, not the plan.

These files are generated and trimmed for readability. To test your own plan, use `../scripts/plan-json.sh <scenario>` (needs AWS credentials) or `terraform show -json plan.tfplan`.
