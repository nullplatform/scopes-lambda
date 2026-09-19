#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  # Create temp dir for mock binaries
  MOCK_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN_DIR"
  export PATH="$MOCK_BIN_DIR:$PATH"
  _TEST_CLEANUP_DIRS=("$MOCK_BIN_DIR")

  # Common variables needed by the script
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export SCOPE_ID="scope-123"
  export SCOPE_SLUG="my-scope"
  export NAMESPACE_SLUG="my-namespace"
  export APPLICATION_SLUG="my-app"
  export ACCOUNT_SLUG="my-account"
  set_context "public"

  # Unset exported shell functions so file-based mocks on PATH take precedence
  unset -f aws np
}

teardown() {
  teardown_test_env
  for dir in "${_TEST_CLEANUP_DIRS[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir"
  done
}

# Helper: create a mock np script
create_np_mock() {
  local responses_file="$MOCK_BIN_DIR/np_responses"
  local index_file="$MOCK_BIN_DIR/np_index"
  echo "0" > "$index_file"
  > "$responses_file"

  # Each argument is a response line: "EXIT_CODE:OUTPUT"
  for resp in "$@"; do
    echo "$resp" >> "$responses_file"
  done

  cat > "$MOCK_BIN_DIR/np" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
INDEX=$(cat "$MOCK_DIR/np_index")
RESPONSE=$(sed -n "$((INDEX + 1))p" "$MOCK_DIR/np_responses")
echo $((INDEX + 1)) > "$MOCK_DIR/np_index"
EXIT_CODE="${RESPONSE%%:*}"
OUTPUT="${RESPONSE#*:}"
if [ "$EXIT_CODE" != "0" ]; then
  echo "$OUTPUT" >&2
  exit "$EXIT_CODE"
fi
echo "$OUTPUT"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

# Helper: create a mock aws script
create_aws_mock() {
  local responses_file="$MOCK_BIN_DIR/aws_responses"
  local index_file="$MOCK_BIN_DIR/aws_index"
  echo "0" > "$index_file"
  > "$responses_file"

  for resp in "$@"; do
    echo "$resp" >> "$responses_file"
  done

  cat > "$MOCK_BIN_DIR/aws" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
INDEX=$(cat "$MOCK_DIR/aws_index")
RESPONSE=$(sed -n "$((INDEX + 1))p" "$MOCK_DIR/aws_responses")
echo $((INDEX + 1)) > "$MOCK_DIR/aws_index"
EXIT_CODE="${RESPONSE%%:*}"
OUTPUT="${RESPONSE#*:}"
if [ "$EXIT_CODE" != "0" ]; then
  echo "$OUTPUT" >&2
  exit "$EXIT_CODE"
fi
echo "$OUTPUT"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

@test "scope/scripts/create_iam_role: uses existing role ARN from NRN" {
  create_np_mock \
    '0:{"AWS_DEDICATED_ROLE_ARN": "arn:aws:iam::123456789012:role/existing-role", "AWS_DEDICATED_ROLE_NAME": "existing-role", "AWS_LAMBDA_USE_DEDICATED_ROLE": "true"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_success
  assert_output_contains "Using existing dedicated role: arn:aws:iam::123456789012:role/existing-role"
}

@test "scope/scripts/create_iam_role: uses default execution role when not using dedicated role" {
  export CONTEXT=$(echo "$MOCK_CONTEXT_PUBLIC" | jq '.providers["cloud-providers"].lambda.execution_role_arn = "arn:aws:iam::123456789012:role/default-lambda-role"')

  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "false"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_success
  assert_output_contains "Using default execution role: arn:aws:iam::123456789012:role/default-lambda-role"
}

@test "scope/scripts/create_iam_role: fails when no role configured and not using dedicated role" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "false"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_failure
  assert_output_contains "No Lambda execution role configured"
  assert_output_contains "No dedicated role enabled via NRN configuration"
  assert_output_contains "No default execution_role_arn set in cloud-provider context"
  assert_output_contains "Enable dedicated roles by setting AWS_LAMBDA_USE_DEDICATED_ROLE=true in NRN"
  assert_output_contains "Or configure lambda.execution_role_arn in cloud-provider"
}

@test "scope/scripts/create_iam_role: creates new dedicated role successfully" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "true", "AWS_LAMBDA_DEDICATED_ROLE_NAME_TEMPLATE": "lambda-{scope_slug}-{scope_id}", "AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}' \
    '0:{"status": "ok"}'

  create_aws_mock \
    '1:NoSuchEntity: Role not found' \
    '0:{"Role": {"Arn": "arn:aws:iam::123456789012:role/lambda-my-scope-scope-123", "RoleName": "lambda-my-scope-scope-123"}}' \
    '0:'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_success
  assert_output_contains "Creating dedicated IAM role..."
  assert_output_contains "role_name=lambda-my-scope-scope-123"
  assert_output_contains "Role created: arn:aws:iam::123456789012:role/lambda-my-scope-scope-123"
  assert_output_contains "Attached AWSLambdaBasicExecutionRole"
  assert_output_contains "Storing role info in NRN..."
  assert_output_contains "IAM role setup complete"
}

@test "scope/scripts/create_iam_role: reuses existing role when already created" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "true", "AWS_LAMBDA_DEDICATED_ROLE_NAME_TEMPLATE": "lambda-{scope_slug}", "AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}' \
    '0:{"status": "ok"}'

  create_aws_mock \
    '0:{"Role": {"Arn": "arn:aws:iam::123456789012:role/lambda-my-scope", "RoleName": "lambda-my-scope"}}'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_success
  assert_output_contains "Role already exists, reusing it"
}

@test "scope/scripts/create_iam_role: fails when create-role AWS call fails" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "true", "AWS_LAMBDA_DEDICATED_ROLE_NAME_TEMPLATE": "lambda-{scope_slug}", "AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}'

  create_aws_mock \
    '1:NoSuchEntity: Role not found' \
    '1:AccessDeniedException: User is not authorized to perform iam:CreateRole'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_failure
  assert_output_contains "Failed to create IAM role"
  assert_output_contains "Insufficient IAM permissions to create roles"
  assert_output_contains "Verify the agent has iam:CreateRole permission"
}

@test "scope/scripts/create_iam_role: fails when attach-role-policy fails" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "true", "AWS_LAMBDA_DEDICATED_ROLE_NAME_TEMPLATE": "lambda-{scope_slug}", "AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}'

  create_aws_mock \
    '1:NoSuchEntity: Role not found' \
    '0:{"Role": {"Arn": "arn:aws:iam::123456789012:role/lambda-my-scope", "RoleName": "lambda-my-scope"}}' \
    '1:AccessDeniedException: Cannot attach policy'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_failure
  assert_output_contains "Failed to attach AWSLambdaBasicExecutionRole"
  assert_output_contains "Insufficient IAM permissions to attach policies"
  assert_output_contains "Verify the agent has iam:AttachRolePolicy permission"
}

@test "scope/scripts/create_iam_role: fails when NRN write fails" {
  create_np_mock \
    '0:{"AWS_LAMBDA_USE_DEDICATED_ROLE": "true", "AWS_LAMBDA_DEDICATED_ROLE_NAME_TEMPLATE": "lambda-{scope_slug}", "AWS_LAMBDA_DEDICATED_ROLE_POLICIES": "[]"}' \
    '1:API error: connection refused'

  create_aws_mock \
    '1:NoSuchEntity: not found' \
    '0:{"Role": {"Arn": "arn:aws:iam::123456789012:role/lambda-my-scope", "RoleName": "lambda-my-scope"}}' \
    '0:'

  run bash "$LAMBDA_DIR/scope/scripts/create_iam_role"

  assert_failure
  assert_output_contains "Failed to store role info in NRN"
  assert_output_contains "NRN service unavailable"
  assert_output_contains "Check nullplatform API connectivity"
}
