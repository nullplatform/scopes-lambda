#!/bin/bash
# Add a missing permission to the sandbox role and log it for the prod request.
#
# Usage:
#   ./tools/add-permission.sh <action> <sid> [resource]
#
# Examples:
#   ./tools/add-permission.sh lambda:GetFunctionCodeSigningConfig LambdaRead
#   ./tools/add-permission.sh "route53:GetChange,route53:ListResourceRecordSets" Route53Read
#   ./tools/add-permission.sh secretsmanager:CreateSecret SecretsManagerCreate "arn:aws:secretsmanager:*:*:secret:nullplatform/*"

set -euo pipefail

PROFILE="kwik"
ROLE="lambda-least-privilege-role"
LOG_FILE="$(dirname "$0")/permissions-log.md"

action_csv="${1:?Usage: $0 <action> <sid> [resource]}"
sid="${2:?Usage: $0 <action> <sid> [resource]}"
resource="${3:-*}"

# Parse comma-separated actions into JSON array
actions_json=$(echo "$action_csv" | jq -Rc 'split(",") | map(select(length > 0))')

# Build the statement
statement=$(jq -n \
  --arg sid "$sid" \
  --argjson actions "$actions_json" \
  --arg resource "$resource" \
  '{Sid: $sid, Effect: "Allow", Action: $actions, Resource: $resource}')

echo "📝 Adding to $ROLE:"
echo "$statement" | jq .

# Fetch current inline policy (or start fresh)
policy_name="iterative-permissions"
current=$(aws iam get-role-policy \
  --role-name "$ROLE" \
  --policy-name "$policy_name" \
  --profile "$PROFILE" \
  --query 'PolicyDocument' \
  --output json 2>/dev/null || echo '{"Version":"2012-10-17","Statement":[]}')

# Check if SID already exists — merge actions if so, otherwise append
existing_idx=$(echo "$current" | jq --arg sid "$sid" '[.Statement[].Sid] | index($sid)')

if [ "$existing_idx" != "null" ]; then
  # Merge new actions into existing statement
  current=$(echo "$current" | jq --arg sid "$sid" --argjson new_actions "$actions_json" '
    .Statement |= map(
      if .Sid == $sid then
        .Action = (.Action + $new_actions | unique)
      else . end
    )')
  echo "   ✅ Merged into existing SID: $sid"
else
  # Append new statement
  current=$(echo "$current" | jq --argjson stmt "$statement" '.Statement += [$stmt]')
  echo "   ✅ Added new SID: $sid"
fi

# Apply to role
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "$policy_name" \
  --policy-document "$current" \
  --profile "$PROFILE"

echo "   ✅ Applied to $ROLE"

# Log for prod request
timestamp=$(date -u +"%Y-%m-%d %H:%M UTC")
{
  echo "| $timestamp | \`$action_csv\` | $sid | \`$resource\` |"
} >> "$LOG_FILE"

echo "   📋 Logged to $(basename "$LOG_FILE")"
echo ""

# Show current full policy
echo "📋 Current iterative-permissions policy:"
echo "$current" | jq .
