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

  # Common required variables
  export LAMBDA_FUNCTION_NAME="my-namespace-my-app-my-scope-scope-123"
  export LAMBDA_ROLE_ARN="arn:aws:iam::123456789012:role/lambda-role"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  _TEST_CLEANUP_DIRS+=("$OUTPUT_DIR")
  export RUNTIME="nodejs20.x"
  export HANDLER="index.handler"
  export ARCHITECTURE="arm64"
  export RESOURCE_TAGS_JSON='{"nullplatform:scope-id":"scope-123","nullplatform:namespace":"my-namespace","nullplatform:application":"my-app","nullplatform:scope":"my-scope"}'

  # Unset exported shell functions so file-based mocks on PATH take precedence
  unset -f aws np
}

teardown() {
  teardown_test_env
  for dir in "${_TEST_CLEANUP_DIRS[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir"
  done
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

# Helper: create a mock zip command (no-op)
create_zip_mock() {
  cat > "$MOCK_BIN_DIR/zip" << 'MOCK_SCRIPT'
#!/bin/bash
# Create an empty file at the target path for the script to find
touch "$3" 2>/dev/null || true
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/zip"
}

@test "scope/scripts/create_placeholder_lambda: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is not set"
  assert_output_contains "build_context did not compute the function name"
  assert_output_contains "Ensure build_context runs before this script"
  assert_output_contains "Check that LAMBDA_FUNCTION_NAME is exported"
}

@test "scope/scripts/create_placeholder_lambda: fails when LAMBDA_ROLE_ARN is not set" {
  unset LAMBDA_ROLE_ARN

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_failure
  assert_output_contains "LAMBDA_ROLE_ARN is not set"
  assert_output_contains "create_iam_role did not run or failed"
  assert_output_contains "Ensure create_iam_role runs before this script"
}

@test "scope/scripts/create_placeholder_lambda: fails when OUTPUT_DIR is not set" {
  unset OUTPUT_DIR

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_failure
  assert_output_contains "OUTPUT_DIR is not set"
  assert_output_contains "The scope runner did not set a working directory"
  assert_output_contains "Ensure OUTPUT_DIR is exported before running this script"
}

@test "scope/scripts/create_placeholder_lambda: skips creation when function already exists" {
  create_aws_mock \
    '0:{"Configuration": {"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-namespace-my-app-my-scope-scope-123", "FunctionName": "my-namespace-my-app-my-scope-scope-123"}}'

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_success
  assert_output_contains "Function already exists - skipping creation"
  assert_output_contains "function_arn=arn:aws:lambda:us-east-1:123456789012:function:my-namespace-my-app-my-scope-scope-123"
}

@test "scope/scripts/create_placeholder_lambda: creates function successfully" {
  create_aws_mock \
    '1:ResourceNotFoundException: Function not found' \
    '0:{"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-namespace-my-app-my-scope-scope-123", "FunctionName": "my-namespace-my-app-my-scope-scope-123"}' \
    '0:{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-namespace-my-app-my-scope-scope-123:main"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_success
  assert_output_contains "Creating placeholder Lambda function..."
  assert_output_contains "function_name=$LAMBDA_FUNCTION_NAME"
  assert_output_contains "role_arn=$LAMBDA_ROLE_ARN"
  assert_output_contains "Placeholder code created and packaged"
  assert_output_contains "Function created: function_arn=arn:aws:lambda:us-east-1:123456789012:function:my-namespace-my-app-my-scope-scope-123"
  assert_output_contains "Alias 'main' created"
  assert_output_contains "Placeholder Lambda created"
}

@test "scope/scripts/create_placeholder_lambda: rolls back on creation failure" {
  create_aws_mock \
    '1:ResourceNotFoundException: Function not found' \
    '1:AccessDeniedException: User not authorized'

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_failure
  assert_output_contains "Failed to create Lambda function"
  assert_output_contains "Insufficient permissions to create Lambda functions"
  assert_output_contains "Verify the agent has lambda:CreateFunction permission"
  assert_output_contains "Rolling back: cleaning up resources..."
}

@test "scope/scripts/create_placeholder_lambda: logs runtime, handler, and architecture" {
  create_aws_mock \
    '1:ResourceNotFoundException: Function not found' \
    '0:{"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:test", "FunctionName": "test"}' \
    '0:{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:test:main"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_success
  assert_output_contains "runtime=nodejs20.x"
  assert_output_contains "handler=index.handler"
  assert_output_contains "architecture=arm64"
}

@test "scope/scripts/create_placeholder_lambda: uses custom alias name from environment" {
  export LAMBDA_MAIN_ALIAS_NAME="production"

  create_aws_mock \
    '1:ResourceNotFoundException: Function not found' \
    '0:{"FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:test", "FunctionName": "test"}' \
    '0:{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:test:production"}'

  run bash "$LAMBDA_DIR/scope/scripts/create_placeholder_lambda"

  assert_success
  assert_output_contains "Alias 'production' created"
}
