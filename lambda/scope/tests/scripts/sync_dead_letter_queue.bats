#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/sync_dead_letter_queue"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  export LAMBDA_FUNCTION_NAME="my-test-function"
  ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

context_with_dlq() {
  export CONTEXT="{\"scope\":{\"capabilities\":{\"dead_letter_target_arn\":\"$1\"}}}"
}

function_with_dlq() {
  local current="${1:-}"
  local dlq_block="null"
  [ -n "$current" ] && dlq_block="{\"TargetArn\":\"$current\"}"
  aws_mock_response "lambda get-function-configuration" 0 \
    "{\"FunctionArn\":\"arn:aws:lambda:us-east-1:111122223333:function:my-test-function\",\"Role\":\"$ROLE_ARN\",\"DeadLetterConfig\":$dlq_block}"
}

@test "sync_dead_letter_queue: sets an SQS target and grants sqs:SendMessage on it only" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_sourced

  assert_success
  assert_aws_cli_called "iam put-role-policy"
  assert_aws_cli_called "sqs:SendMessage"
  assert_aws_cli_called "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  assert_aws_cli_called "--dead-letter-config TargetArn=arn:aws:sqs:us-east-1:111122223333:my-dlq"
  assert_aws_cli_called "--role-name np-lambda-my-test-function-role"
}

@test "sync_dead_letter_queue: grants sns:Publish for an SNS target" {
  context_with_dlq "arn:aws:sns:us-east-1:111122223333:my-topic"
  function_with_dlq

  run_sourced

  assert_success
  assert_aws_cli_called "sns:Publish"
  assert_aws_cli_not_called "sqs:SendMessage"
}

@test "sync_dead_letter_queue: grants access before enabling the queue" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_sourced

  assert_success
  # Lambda drops failed events if the role cannot write yet, so the grant has
  # to land first.
  grant_line=$(grep -n "iam put-role-policy" "$MOCK_BIN_DIR/aws_calls" | cut -d: -f1)
  enable_line=$(grep -n "dead-letter-config TargetArn=" "$MOCK_BIN_DIR/aws_calls" | cut -d: -f1)
  [ "$grant_line" -lt "$enable_line" ]
}

@test "sync_dead_letter_queue: is idempotent when the target is already set" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_sourced

  assert_success
  assert_aws_cli_called "iam put-role-policy"
  assert_aws_cli_not_called "update-function-configuration"
  assert_output_contains "up to date"
}

@test "sync_dead_letter_queue: clears the config and the grant when the ARN is empty" {
  context_with_dlq ""
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_sourced

  assert_success
  assert_aws_cli_called "--dead-letter-config {}"
  assert_aws_cli_called "iam delete-role-policy"
  assert_aws_cli_called "--policy-name np-lambda-dlq"
  assert_output_contains "Dead letter queue disabled"
}

@test "sync_dead_letter_queue: does not call Lambda when there is nothing to disable" {
  context_with_dlq ""
  function_with_dlq

  run_sourced

  assert_success
  assert_aws_cli_not_called "update-function-configuration"
  assert_aws_cli_called "iam delete-role-policy"
}

@test "sync_dead_letter_queue: rejects a target that is neither SQS nor SNS" {
  context_with_dlq "arn:aws:s3:::my-bucket"
  function_with_dlq

  run_sourced

  assert_failure
  assert_output_contains "Unsupported dead letter target"
  assert_aws_cli_not_called "update-function-configuration"
}

@test "sync_dead_letter_queue: rejects a queue name that is not an ARN" {
  context_with_dlq "my-dlq"
  function_with_dlq

  run_sourced

  assert_failure
  assert_output_contains "Unsupported dead letter target"
}

@test "sync_dead_letter_queue: never touches code, environment or version" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_sourced

  assert_success
  assert_aws_cli_not_called "update-function-code"
  assert_aws_cli_not_called "--environment"
  assert_aws_cli_not_called "publish-version"
}

@test "sync_dead_letter_queue: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_sourced

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "sync_dead_letter_queue: surfaces a failure reading the function" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"

  run_sourced

  assert_failure
  assert_output_contains "Failed to read configuration"
}

@test "sync_dead_letter_queue: surfaces a denied IAM grant without enabling the queue" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "iam put-role-policy" 254 "AccessDenied"

  run_sourced

  assert_failure
  assert_output_contains "Failed to grant dead letter access"
  assert_aws_cli_not_called "update-function-configuration"
}
