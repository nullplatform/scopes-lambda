#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/store_nrn_metadata"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock
  create_np_mock 0

  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_FUNCTION_NAME="my-test-function"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

create_np_mock() {
  echo "${1:-0}" > "$MOCK_BIN_DIR/np_exit"
  : > "$MOCK_BIN_DIR/np_calls"
  cat > "$MOCK_BIN_DIR/np" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
printf '%s\n' "$*" >> "$MOCK_DIR/np_calls"
exit_code=$(cat "$MOCK_DIR/np_exit")
[ "$exit_code" != "0" ] && { echo "np failed" >&2; exit "$exit_code"; }
echo '{}'
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

np_body() {
  cat "$MOCK_BIN_DIR/np_calls" 2>/dev/null
}

assert_np_body_contains() {
  if ! grep -qF -- "$1" "$MOCK_BIN_DIR/np_calls" 2>/dev/null; then
    echo "Expected the NRN patch body to contain: $1"
    echo "Actual np calls:"
    np_body | sed 's/^/  - np /'
    return 1
  fi
}

assert_np_not_called() {
  if [ -s "$MOCK_BIN_DIR/np_calls" ]; then
    echo "Expected no np call, but got:"
    np_body | sed 's/^/  - np /'
    return 1
  fi
}

# The create path: do_tofu exported everything, no AWS lookups needed.
with_tofu_outputs() {
  export LAMBDA_FUNCTION_ARN="arn:aws:lambda:us-east-1:111122223333:function:my-test-function"
  export LAMBDA_ALIAS_ARN="arn:aws:lambda:us-east-1:111122223333:function:my-test-function:main"
  export LAMBDA_EXECUTION_ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"
  export LAMBDA_EXECUTION_ROLE_NAME="np-lambda-my-test-function-role"
  export LAMBDA_MAIN_ALIAS_NAME="main"
}

@test "store_nrn_metadata: publishes the scope identity under the lambda namespace" {
  with_tofu_outputs

  run_sourced

  assert_success
  assert_np_body_contains "lambda.function_name"
  assert_np_body_contains "lambda.alias_arn"
  assert_np_body_contains "lambda.execution_role_arn"
  assert_np_body_contains "arn:aws:lambda:us-east-1:111122223333:function:my-test-function:main"
  assert_aws_cli_not_called "get-alias"
}

@test "store_nrn_metadata: defaults the alias name to main" {
  with_tofu_outputs
  unset LAMBDA_MAIN_ALIAS_NAME

  run_sourced

  assert_success
  assert_np_body_contains '"lambda.main_alias":"main"'
}

@test "store_nrn_metadata: omits the ALB priority on event-driven scopes" {
  with_tofu_outputs

  run_sourced

  assert_success
  assert_np_body_contains "lambda.function_arn"
  run bash -c "grep -qF 'alb_rule_priority' '$MOCK_BIN_DIR/np_calls'"
  assert_failure
}

@test "store_nrn_metadata: keeps storing the ALB priority as a number" {
  with_tofu_outputs
  export ALB_RULE_PRIORITY=142

  run_sourced

  assert_success
  assert_np_body_contains '"lambda.alb_rule_priority":142'
}

# The update path: no tofu run, so identity has to come from AWS. This is also
# what backfills scopes created before this script published identity.
@test "store_nrn_metadata: backfills identity from AWS when tofu outputs are absent" {
  aws_mock_response "lambda get-function-configuration" 0 \
    '{"FunctionArn":"arn:aws:lambda:us-east-1:111122223333:function:my-test-function","Role":"arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"}'
  aws_mock_response "lambda get-alias" 0 \
    "arn:aws:lambda:us-east-1:111122223333:function:my-test-function:main"

  run_sourced

  assert_success
  assert_aws_cli_called "get-function-configuration"
  assert_aws_cli_called "get-alias"
  assert_np_body_contains "arn:aws:lambda:us-east-1:111122223333:function:my-test-function:main"
  assert_np_body_contains '"lambda.execution_role_name":"np-lambda-my-test-function-role"'
}

@test "store_nrn_metadata: still stores the name when AWS lookups fail" {
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"
  aws_mock_response "lambda get-alias" 254 "ResourceNotFoundException"

  run_sourced

  assert_success
  assert_np_body_contains '"lambda.function_name":"my-test-function"'
}

@test "store_nrn_metadata: skips the patch when nothing resolves" {
  unset LAMBDA_FUNCTION_NAME

  run_sourced

  assert_success
  assert_np_not_called
}

@test "store_nrn_metadata: fails when SCOPE_NRN is not set" {
  unset SCOPE_NRN
  with_tofu_outputs

  run_sourced

  assert_failure
  assert_output_contains "SCOPE_NRN is required"
}

@test "store_nrn_metadata: surfaces an NRN patch failure" {
  with_tofu_outputs
  create_np_mock 1

  run_sourced

  assert_failure
  assert_output_contains "Failed to write NRN metadata"
}

@test "store_nrn_metadata: a bad ALB priority does not take the identity down with it" {
  with_tofu_outputs
  export ALB_RULE_PRIORITY="not-a-number"

  run_sourced

  assert_success
  # jq --argjson would fail on this and blank the whole payload, dropping the
  # keys other services read — while still reporting success.
  assert_np_body_contains "lambda.alias_arn"
  run bash -c "grep -qF 'alb_rule_priority' '$MOCK_BIN_DIR/np_calls'"
  assert_failure
}
