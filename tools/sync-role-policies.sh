#!/bin/bash
# Sync IAM policies from one role to another across accounts.
# Copies inline policies and replaces account IDs in resource ARNs.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
SOURCE_PROFILE="null_runtime_main"
SOURCE_ROLE="custom-scope-role"
SOURCE_ACCOUNT="283477532906"

TARGET_PROFILE="kwik"
TARGET_ROLE="lambda-least-privilege-role"
TARGET_ACCOUNT="688720756067"
# ───────────────────────────────────────────────────────────────

echo "🔍 Syncing policies: $SOURCE_ROLE ($SOURCE_ACCOUNT) → $TARGET_ROLE ($TARGET_ACCOUNT)"
echo ""

# 1. Fetch inline policy names from source role
echo "📡 Listing inline policies on source role..."
inline_policies=$(aws iam list-role-policies \
  --role-name "$SOURCE_ROLE" \
  --profile "$SOURCE_PROFILE" \
  --query 'PolicyNames' \
  --output json)

policy_count=$(echo "$inline_policies" | jq 'length')
echo "   Found $policy_count inline policies"
echo ""

# 2. Copy each inline policy to target role
echo "$inline_policies" | jq -r '.[]' | while read -r policy_name; do
  echo "📝 Processing inline policy: $policy_name"

  # Fetch policy document from source
  policy_doc=$(aws iam get-role-policy \
    --role-name "$SOURCE_ROLE" \
    --policy-name "$policy_name" \
    --profile "$SOURCE_PROFILE" \
    --query 'PolicyDocument' \
    --output json)

  # Replace source account with target account in resource ARNs
  policy_doc=$(echo "$policy_doc" | sed "s/$SOURCE_ACCOUNT/$TARGET_ACCOUNT/g")

  echo "   ✅ Account $SOURCE_ACCOUNT → $TARGET_ACCOUNT in resource ARNs"

  # Put policy on target role
  aws iam put-role-policy \
    --role-name "$TARGET_ROLE" \
    --policy-name "$policy_name" \
    --policy-document "$policy_doc" \
    --profile "$TARGET_PROFILE"

  echo "   ✅ Applied to $TARGET_ROLE"
  echo ""
done

# 3. Fetch managed policy attachments from source role
echo "📡 Listing managed policy attachments on source role..."
managed_policies=$(aws iam list-attached-role-policies \
  --role-name "$SOURCE_ROLE" \
  --profile "$SOURCE_PROFILE" \
  --query 'AttachedPolicies' \
  --output json)

managed_count=$(echo "$managed_policies" | jq 'length')
echo "   Found $managed_count managed policies"
echo ""

echo "$managed_policies" | jq -r '.[].PolicyArn' | while read -r policy_arn; do
  echo "📝 Processing managed policy: $policy_arn"

  if [[ "$policy_arn" == arn:aws:iam::aws:policy/* ]]; then
    # AWS managed policy — attach directly (same ARN in all accounts)
    aws iam attach-role-policy \
      --role-name "$TARGET_ROLE" \
      --policy-arn "$policy_arn" \
      --profile "$TARGET_PROFILE" 2>/dev/null || true
    echo "   ✅ Attached AWS managed policy"
  else
    # Customer managed policy — fetch, rewrite account, create in target
    target_arn=$(echo "$policy_arn" | sed "s/$SOURCE_ACCOUNT/$TARGET_ACCOUNT/g")
    policy_name=$(echo "$policy_arn" | awk -F'/' '{print $NF}')

    # Get the current policy version document
    version_id=$(aws iam get-policy \
      --policy-arn "$policy_arn" \
      --profile "$SOURCE_PROFILE" \
      --query 'Policy.DefaultVersionId' \
      --output text)

    policy_doc=$(aws iam get-policy-version \
      --policy-arn "$policy_arn" \
      --version-id "$version_id" \
      --profile "$SOURCE_PROFILE" \
      --query 'PolicyVersion.Document' \
      --output json)

    # Replace account in resource ARNs
    policy_doc=$(echo "$policy_doc" | sed "s/$SOURCE_ACCOUNT/$TARGET_ACCOUNT/g")

    # Create or update in target account
    if aws iam get-policy --policy-arn "$target_arn" --profile "$TARGET_PROFILE" &>/dev/null; then
      # Policy exists — create new version and set as default
      aws iam create-policy-version \
        --policy-arn "$target_arn" \
        --policy-document "$policy_doc" \
        --set-as-default \
        --profile "$TARGET_PROFILE" 2>/dev/null || {
          # Max 5 versions — delete oldest non-default and retry
          oldest=$(aws iam list-policy-versions \
            --policy-arn "$target_arn" \
            --profile "$TARGET_PROFILE" \
            --query 'Versions[?IsDefaultVersion==`false`] | [0].VersionId' \
            --output text)
          if [ -n "$oldest" ] && [ "$oldest" != "None" ]; then
            aws iam delete-policy-version \
              --policy-arn "$target_arn" \
              --version-id "$oldest" \
              --profile "$TARGET_PROFILE"
            aws iam create-policy-version \
              --policy-arn "$target_arn" \
              --policy-document "$policy_doc" \
              --set-as-default \
              --profile "$TARGET_PROFILE"
          fi
        }
      echo "   ✅ Updated existing policy in target"
    else
      # Policy doesn't exist — create it
      aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$policy_doc" \
        --profile "$TARGET_PROFILE" >/dev/null
      echo "   ✅ Created policy in target"
    fi

    # Attach to target role
    aws iam attach-role-policy \
      --role-name "$TARGET_ROLE" \
      --policy-arn "$target_arn" \
      --profile "$TARGET_PROFILE" 2>/dev/null || true
    echo "   ✅ Attached to $TARGET_ROLE"
  fi
  echo ""
done

echo "✨ Sync complete: $SOURCE_ROLE → $TARGET_ROLE"
echo ""
echo "📋 Verify with:"
echo "   aws iam list-role-policies --role-name $TARGET_ROLE --profile $TARGET_PROFILE"
echo "   aws iam list-attached-role-policies --role-name $TARGET_ROLE --profile $TARGET_PROFILE"
