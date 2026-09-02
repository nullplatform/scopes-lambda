#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/merge_iam_policies"

  # Create temp dir for file-based mocks
  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Track call count for multi-response mocks
  MOCK_STATE_DIR="$(mktemp -d)"

  # Unset exported functions so PATH-based mocks take precedence
  unset -f aws np
}

teardown() {
  teardown_test_env
  rm -rf "$MOCK_BIN_DIR" "$MOCK_STATE_DIR"
}

# Helper: create a mock np script with sequential responses
# Usage: create_np_mock "response1" "response2" ...
create_np_mock() {
  local state_file="$MOCK_STATE_DIR/np_call_index"
  echo "0" > "$state_file"

  local i=0
  for response in "$@"; do
    echo "$response" > "$MOCK_STATE_DIR/np_response_$i"
    i=$((i + 1))
  done

  cat > "$MOCK_BIN_DIR/np" <<OUTERSCRIPT
#!/bin/bash
STATE_FILE="$MOCK_STATE_DIR/np_call_index"
idx=\$(cat "\$STATE_FILE")
RESPONSE_FILE="$MOCK_STATE_DIR/np_response_\$idx"
next_idx=\$((idx + 1))
echo "\$next_idx" > "\$STATE_FILE"
if [ -f "\$RESPONSE_FILE" ]; then
  cat "\$RESPONSE_FILE"
  exit 0
fi
echo "{}"
exit 0
OUTERSCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

# Helper: create a mock np that fails
create_np_error_mock() {
  local error_message="${1:-An error occurred}"
  echo "$error_message" > "$MOCK_BIN_DIR/np_error.txt"
  cat > "$MOCK_BIN_DIR/np" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/np_error.txt" >&2
exit 1
OUTERSCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

# Helper: create a mock aws script
create_aws_mock() {
  local response="$1"
  local exit_code="${2:-0}"
  echo "$response" > "$MOCK_BIN_DIR/aws_response.txt"
  cat > "$MOCK_BIN_DIR/aws" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/aws_response.txt"
OUTERSCRIPT
  echo "exit $exit_code" >> "$MOCK_BIN_DIR/aws"
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Helper: create a mock aws that fails
create_aws_error_mock() {
  local error_message="$1"
  echo "$error_message" > "$MOCK_BIN_DIR/aws_error.txt"
  cat > "$MOCK_BIN_DIR/aws" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/aws_error.txt" >&2
exit 1
OUTERSCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# These scripts are sourced by the workflow engine, so `return` is their exit
# path. `run bash <script>` turns `return` into a warning and keeps going, so a
# failure assertion could never observe the non-zero status.
run_sourced() {
  run bash -c "source '$1'"
}

@test "deployment/scripts/merge_iam_policies: fails when LAMBDA_ROLE_NAME is not set" {
  unset LAMBDA_ROLE_NAME
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  run_sourced "$SCRIPT"

  assert_failure
  assert_line "❌ LAMBDA_ROLE_NAME is required"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Environment variable not set by the deployment pipeline"
  assert_output_contains "Lambda execution role was not created during scope provisioning"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Verify the scope has a valid IAM role configured"
  assert_output_contains "Check that LAMBDA_ROLE_NAME is exported before this script runs"
}

@test "deployment/scripts/merge_iam_policies: fails when DEPLOYMENT_ID is not set" {
  export LAMBDA_ROLE_NAME="my-role"
  unset DEPLOYMENT_ID
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  run_sourced "$SCRIPT"

  assert_failure
  assert_line "❌ DEPLOYMENT_ID is required"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Deployment context not properly initialized"
  assert_output_contains "Script invoked outside of a deployment pipeline"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Ensure this script is called from within a nullplatform deployment flow"
  assert_output_contains "Check that DEPLOYMENT_ID is set in the environment"
}

@test "deployment/scripts/merge_iam_policies: fails when SCOPE_NRN is not set" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  unset SCOPE_NRN

  run_sourced "$SCRIPT"

  assert_failure
  assert_line "❌ SCOPE_NRN is required"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Scope context not available in the environment"
  assert_output_contains "NRN not passed from the deployment pipeline"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Verify SCOPE_NRN is exported before this script runs"
  assert_output_contains "Check the deployment agent configuration"
}

@test "deployment/scripts/merge_iam_policies: skips when no deployment-specific policies found" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No deployment-specific policies to merge"
}

@test "deployment/scripts/merge_iam_policies: skips when policies is null" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": null}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No deployment-specific policies to merge"
}

@test "deployment/scripts/merge_iam_policies: attaches single policy successfully" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock \
    '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[{\"name\":\"sqs-access\",\"policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[]}\"}]"}' \
    '{}'
  create_aws_mock ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "📝 Merging IAM policies for deployment..."
  assert_output_contains "role_name=my-role"
  assert_output_contains "deployment_id=deploy-123"
  assert_output_contains "Found 1 policies to merge for role=my-role"
  assert_output_contains "Attaching policy: sqs-access-deploy-123 to role=my-role"
  assert_output_contains "Policy sqs-access-deploy-123 attached successfully"
  assert_output_contains "✨ IAM policies merged successfully for role=my-role deployment=deploy-123"
}

@test "deployment/scripts/merge_iam_policies: logs policy attachment with correct naming convention" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock \
    '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[{\"name\":\"sqs-access\",\"policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[]}\"}]"}' \
    '{}'
  create_aws_mock ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Attaching policy: sqs-access-deploy-123 to role=my-role"
  assert_output_contains "Policy sqs-access-deploy-123 attached successfully"
}

@test "deployment/scripts/merge_iam_policies: fails when aws put-role-policy fails" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock \
    '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[{\"name\":\"sqs-access\",\"policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[]}\"}]"}'
  create_aws_error_mock "NoSuchEntityException: Role my-role does not exist"

  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "❌ Failed to attach policy sqs-access-deploy-123 to role my-role"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "IAM role my-role does not exist"
  assert_output_contains "Policy document is malformed"
  assert_output_contains "Insufficient IAM permissions to modify role"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Verify the role exists: aws iam get-role --role-name my-role"
  assert_output_contains "Validate the policy document JSON"
  assert_output_contains "Check the agent's IAM permissions include iam:PutRolePolicy"
}

@test "deployment/scripts/merge_iam_policies: logs deployment-scoped NRN in output" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Reading deployment policies from NRN=organization=1:account=2:namespace=3:application=4:scope=5:deployment=deploy-123..."
}

@test "deployment/scripts/merge_iam_policies: stores merged policies in deployment NRN" {
  export LAMBDA_ROLE_NAME="my-role"
  export DEPLOYMENT_ID="deploy-123"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock \
    '{"AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[{\"name\":\"sqs-access\",\"policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[]}\"}]"}' \
    '{}'
  create_aws_mock ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Storing policies in deployment NRN=organization=1:account=2:namespace=3:application=4:scope=5:deployment=deploy-123..."
}
