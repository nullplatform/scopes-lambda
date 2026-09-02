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
  export SCOPE_ID="9001"
  SCOPE_ROLE="np-lambda-my-test-function-role"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

on_role() {
  aws_mock_response "lambda get-function-configuration" 0 "arn:aws:iam::111122223333:role/$1"
}

with_inline_policies() {
  aws_mock_response "iam list-role-policies" 0 "$1"
}

@test "cleanup_role_inline_policies: clears every policy on the scope's own role" {
  on_role "$SCOPE_ROLE"
  # merge_iam_policies names its policies <name>-<deployment_id>, so a static
  # list would leave them behind and DeleteRole would fail.
  with_inline_policies "np-lambda-dlq-9001	app-policy-4242"

  run_sourced

  assert_success
  assert_aws_cli_called "--policy-name np-lambda-dlq-9001"
  assert_aws_cli_called "--policy-name app-policy-4242"
}

@test "cleanup_role_inline_policies: touches only its own policy on a shared role" {
  on_role "shared-lambda-role"
  with_inline_policies "np-lambda-dlq-9001	np-lambda-dlq-7777	someone-elses-policy"

  run_sourced

  assert_success
  assert_aws_cli_called "--policy-name np-lambda-dlq-9001"
  # Another scope's grant and unrelated policies must survive
  assert_aws_cli_not_called "--policy-name np-lambda-dlq-7777"
  assert_aws_cli_not_called "--policy-name someone-elses-policy"
}

@test "cleanup_role_inline_policies: derives the role name when the function is gone" {
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"
  with_inline_policies "np-lambda-dlq-9001"

  run_sourced

  assert_success
  assert_aws_cli_called "--role-name $SCOPE_ROLE"
}

@test "cleanup_role_inline_policies: honours a custom execution role prefix" {
  export LAMBDA_EXECUTION_ROLE_PREFIX="nullplatform-"
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"
  with_inline_policies "np-lambda-dlq-9001"

  run_sourced

  assert_success
  assert_aws_cli_called "--role-name nullplatform-my-test-function-role"
}

@test "cleanup_role_inline_policies: no-op when the role has no inline policies" {
  on_role "$SCOPE_ROLE"
  with_inline_policies ""

  run_sourced

  assert_success
  assert_aws_cli_not_called "delete-role-policy"
}

@test "cleanup_role_inline_policies: a failed delete is reported, not fatal" {
  on_role "$SCOPE_ROLE"
  with_inline_policies "np-lambda-dlq-9001"
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
