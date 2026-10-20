#!/usr/bin/env bash
# Render a scenario's plan as JSON, the same shape env0 hands to approval policies.
#
#   scripts/plan-json.sh 02-public-bucket > /tmp/plan.json
#
# Needs AWS credentials (the app reads the default VPC and an AMI).
# Set TF=tofu to use OpenTofu.
set -euo pipefail

scenario="${1:?usage: plan-json.sh <scenario> (e.g. 02-public-bucket)}"
tf="${TF:-terraform}"
root="$(cd "$(dirname "$0")/.." && pwd)"
varfile="$root/app/scenarios/$scenario.tfvars"
planfile="$(mktemp)"
trap 'rm -f "$planfile"' EXIT

[ -f "$varfile" ] || { echo "no such scenario: $varfile" >&2; exit 1; }

cd "$root/app"
"$tf" init -backend=false -input=false >&2
"$tf" plan -input=false -var-file="$varfile" -out="$planfile" >&2
"$tf" show -json "$planfile"
