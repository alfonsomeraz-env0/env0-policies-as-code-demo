# Expect PENDING in prod: production/destructive. Deploy 01-clean first, then redeploy with this
# so the plan deletes the logs bucket. In dev the same change is auto-approved.
create_logs_bucket = false
