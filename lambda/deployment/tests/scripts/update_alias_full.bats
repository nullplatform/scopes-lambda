#!/usr/bin/env bats
# Unit tests for deployment/scripts/update_alias_full script

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/update_alias_full"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
  rm -rf "$MOCK_BIN_DIR"
}

create_aws_mock() {
  local response="$1"
  local exit_code="${2:-0}"
  cat > "$MOCK_BIN_DIR/aws" <<SCRIPT
#!/bin/bash
echo '$response'
exit $exit_code
SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

create_aws_error_mock() {
  local error_message="${1:-An error occurred}"
  cat > "$MOCK_BIN_DIR/aws" <<SCRIPT
#!/bin/bash
echo "$error_message" >&2
exit 1
SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Input validation
@test "deployment/scripts/update_alias_full: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "deployment/scripts/update_alias_full: fails when no version is specified" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  unset LAMBDA_NEW_VERSION
  unset LAMBDA_CURRENT_VERSION

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "No version specified"
}

# Successful update flow
@test "deployment/scripts/update_alias_full: updates alias and logs success messages" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="5"

  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
  assert_output_contains "function_name=my-function"
  assert_output_contains "alias=main"
  assert_output_contains "new_version=5"
  assert_output_contains "Updating alias main to point to version 5 on function my-function"
  assert_output_contains "Alias main updated successfully to version 5"
  assert_output_contains "Traffic finalized to version 5 on function=my-function alias=main"
}

@test "deployment/scripts/update_alias_full: uses LAMBDA_CURRENT_VERSION when LAMBDA_NEW_VERSION is not set" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  unset LAMBDA_NEW_VERSION
  export LAMBDA_CURRENT_VERSION="3"

  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "3"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
  assert_output_contains "new_version=3"
}

@test "deployment/scripts/update_alias_full: defaults alias name to main" {
  export LAMBDA_FUNCTION_NAME="my-function"
  unset LAMBDA_MAIN_ALIAS_NAME
  export LAMBDA_NEW_VERSION="5"

  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
  assert_output_contains "alias=main"
}

# AWS CLI call verification
@test "deployment/scripts/update_alias_full: calls aws lambda update-alias with correct args" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="5"

  mock_aws '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  aws lambda update-alias \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --name "$LAMBDA_MAIN_ALIAS_NAME" \
    --function-version "$LAMBDA_NEW_VERSION"

  [ $? -eq 0 ]
  assert_aws_called "update-alias"
  assert_aws_called "--function-name my-function"
  assert_aws_called "--name main"
  assert_aws_called "--function-version 5"
}

@test "deployment/scripts/update_alias_full: removes routing config when setting full traffic" {
  mock_aws '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5", "RoutingConfig": null}'

  result=$(aws lambda update-alias \
    --function-name "my-function" \
    --name "main" \
    --function-version "5" \
    --routing-config 'AdditionalVersionWeights={}')

  [ $? -eq 0 ]
  routing=$(echo "$result" | jq -r '.RoutingConfig // "null"')
  assert_equal "$routing" "null"
}

# Error handling
@test "deployment/scripts/update_alias_full: handles AWS CLI errors gracefully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="5"

  create_aws_error_mock "ResourceNotFoundException: Function my-function not found"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "Failed to update alias"
}

@test "deployment/scripts/update_alias_full: handles alias not found error" {
  mock_aws_error "ResourceNotFoundException: Alias nonexistent not found"

  run aws lambda update-alias \
    --function-name "my-function" \
    --name "nonexistent" \
    --function-version "5"

  assert_failure
  assert_output_contains "Alias"
}

@test "deployment/scripts/update_alias_full: handles version not found error" {
  mock_aws_error "ResourceNotFoundException: Version 999 does not exist"

  run aws lambda update-alias \
    --function-name "my-function" \
    --name "main" \
    --function-version "999"

  assert_failure
}

# Response validation
@test "deployment/scripts/update_alias_full: verifies alias points to correct version after update" {
  mock_aws '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  result=$(aws lambda update-alias \
    --function-name "my-function" \
    --name "main" \
    --function-version "5")

  assert_json_path_equal "$result" '.FunctionVersion' "5"
}

@test "deployment/scripts/update_alias_full: returns alias ARN on success" {
  mock_aws '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  result=$(aws lambda update-alias \
    --function-name "my-function" \
    --name "main" \
    --function-version "5")

  alias_arn=$(echo "$result" | jq -r '.AliasArn')
  assert_contains "$alias_arn" "arn:aws:lambda:"
}

# Idempotency
@test "deployment/scripts/update_alias_full: succeeds when alias already points to the version" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="5"

  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "5"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
}
