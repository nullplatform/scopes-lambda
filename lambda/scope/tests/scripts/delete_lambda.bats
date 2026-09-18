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

  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

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

@test "scope/scripts/delete_lambda: skips when no function name found in NRN or environment" {
  create_np_mock \
    '0:{"some_other_key": "value"}'
  unset LAMBDA_FUNCTION_NAME

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "No Lambda function name found in NRN or environment - skipping deletion"
}

@test "scope/scripts/delete_lambda: skips when function does not exist in AWS" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_NAME": "my-function"}'

  create_aws_mock \
    '1:ResourceNotFoundException: Function not found'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "Function 'my-function' does not exist - skipping deletion"
}

@test "scope/scripts/delete_lambda: falls back to LAMBDA_FUNCTION_NAME env var" {
  create_np_mock \
    '0:{}'
  export LAMBDA_FUNCTION_NAME="env-function-name"

  create_aws_mock \
    '1:ResourceNotFoundException: Function not found'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "function_name=env-function-name"
  assert_output_contains "Function 'env-function-name' does not exist - skipping deletion"
}

@test "scope/scripts/delete_lambda: deletes function with aliases successfully" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_NAME": "my-function"}'

  create_aws_mock \
    '0:{"Configuration": {"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function"}}' \
    '0:main warmup' \
    '0:' \
    '0:' \
    '0:'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "Deleting Lambda function..."
  assert_output_contains "function_name=my-function"
  assert_output_contains "Deleting aliases for 'my-function'..."
  assert_output_contains "Deleting alias: main"
  assert_output_contains "Deleting alias: warmup"
  assert_output_contains "Deleting Lambda function 'my-function'..."
  assert_output_contains "Lambda function 'my-function' deleted successfully"
  assert_output_contains "Lambda cleanup complete"
}

@test "scope/scripts/delete_lambda: deletes function with no aliases" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_NAME": "my-function"}'

  create_aws_mock \
    '0:{"Configuration": {"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function"}}' \
    '0:' \
    '0:'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "No aliases found"
  assert_output_contains "Lambda function 'my-function' deleted successfully"
}

@test "scope/scripts/delete_lambda: fails when delete-function AWS call fails" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_NAME": "my-function"}'

  create_aws_mock \
    '0:{"Configuration": {"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function"}}' \
    '0:' \
    '1:ResourceConflictException: Function is being updated'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_failure
  assert_output_contains "Failed to delete Lambda function 'my-function'"
  assert_output_contains "Function is being invoked or updated concurrently"
  assert_output_contains "Insufficient Lambda permissions"
  assert_output_contains "Wait for ongoing operations to complete and retry"
  assert_output_contains "Verify the agent has lambda:DeleteFunction permission"
}

@test "scope/scripts/delete_lambda: handles NRN read failure gracefully" {
  create_np_mock \
    '1:API unavailable'
  export LAMBDA_FUNCTION_NAME="fallback-function"

  create_aws_mock \
    '1:ResourceNotFoundException: not found'

  run bash "$LAMBDA_DIR/scope/scripts/delete_lambda"

  assert_success
  assert_output_contains "function_name=fallback-function"
}
