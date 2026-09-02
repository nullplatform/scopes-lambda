#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/cleanup_role_inline_policies"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  export CONTEXT='{}'
  export LAMBDA_FUNCTION_NAME="my-test-function"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_sourced() {
  run bash -c "source '$SCRIPT'"
}

@test "cleanup_role_inline_policies: removes the DLQ policy from the function's role" {
  aws_mock_response "lambda get-function-configuration" 0 \
    "arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"

  run_sourced

  assert_success
  assert_aws_cli_called "iam delete-role-policy"
  assert_aws_cli_called "--role-name np-lambda-my-test-function-role"
  assert_aws_cli_called "--policy-name np-lambda-dlq"
}

@test "cleanup_role_inline_policies: derives the role name when the function is already gone" {
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"

  run_sourced

  assert_success
  assert_aws_cli_called "--role-name np-lambda-my-test-function-role"
}

@test "cleanup_role_inline_policies: honours a custom execution role prefix" {
  export LAMBDA_EXECUTION_ROLE_PREFIX="nullplatform-"
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"

  run_sourced

  assert_success
  assert_aws_cli_called "--role-name nullplatform-my-test-function-role"
}

@test "cleanup_role_inline_policies: a missing policy is not an error" {
  aws_mock_response "lambda get-function-configuration" 0 \
    "arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"
  aws_mock_response "iam delete-role-policy" 254 "NoSuchEntity"

  run_sourced

  assert_success
}

@test "cleanup_role_inline_policies: no-op without a function name" {
  unset LAMBDA_FUNCTION_NAME

  run_sourced

  assert_success
  assert_aws_cli_not_called "delete-role-policy"
}
