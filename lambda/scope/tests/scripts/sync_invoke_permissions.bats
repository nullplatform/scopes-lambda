#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/sync_invoke_permissions"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  export LAMBDA_FUNCTION_NAME="my-test-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

context_with() {
  export CONTEXT="{\"providers\":{\"scope-configurations\":{\"lambda\":{\"triggers\":{\"invoke_permissions\":$1}}}}}"
}

no_policy() {
  aws_mock_response "lambda get-policy" 254 "ResourceNotFoundException: The resource you requested does not exist."
}

with_policy() {
  aws_mock_response "lambda get-policy" 0 "$1"
}

@test "sync_invoke_permissions: no declared permissions and no policy is a no-op" {
  context_with '[]'
  no_policy

  run_sourced

  assert_success
  assert_aws_cli_not_called "add-permission"
  assert_aws_cli_not_called "remove-permission"
  assert_output_contains "0 declared"
}

@test "sync_invoke_permissions: adds a declared permission against the main alias" {
  context_with '[{"statement_id":"apigw-authorizer","principal":"apigateway.amazonaws.com","source_arn":"arn:aws:execute-api:us-east-1:111122223333:abcd/authorizers/*"}]'
  no_policy

  run_sourced

  assert_success
  assert_aws_cli_called "add-permission"
  assert_aws_cli_called "--statement-id np-ext-apigw-authorizer"
  assert_aws_cli_called "--principal apigateway.amazonaws.com"
  assert_aws_cli_called "--source-arn arn:aws:execute-api:us-east-1:111122223333:abcd/authorizers/*"
  # Blue/green: the grant must target the alias, never the bare function
  assert_aws_cli_called "--qualifier main"
}

@test "sync_invoke_permissions: defaults the action to lambda:InvokeFunction" {
  context_with '[{"statement_id":"eventbridge-daily","principal":"events.amazonaws.com"}]'
  no_policy

  run_sourced

  assert_success
  assert_aws_cli_called "--action lambda:InvokeFunction"
}

@test "sync_invoke_permissions: passes source_account when declared" {
  context_with '[{"statement_id":"s3-uploads","principal":"s3.amazonaws.com","source_arn":"arn:aws:s3:::my-bucket","source_account":"111122223333"}]'
  no_policy

  run_sourced

  assert_success
  assert_aws_cli_called "--source-account 111122223333"
}

@test "sync_invoke_permissions: leaves an already-matching permission untouched" {
  context_with '[{"statement_id":"eventbridge-daily","principal":"events.amazonaws.com","source_arn":"arn:aws:events:us-east-1:111122223333:rule/daily"}]'
  with_policy '{"Statement":[{"Sid":"np-ext-eventbridge-daily","Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"lambda:InvokeFunction","Condition":{"ArnLike":{"AWS:SourceArn":"arn:aws:events:us-east-1:111122223333:rule/daily"}}}]}'

  run_sourced

  assert_success
  assert_aws_cli_not_called "add-permission"
  assert_aws_cli_not_called "remove-permission"
}

@test "sync_invoke_permissions: replaces a permission whose source_arn changed" {
  context_with '[{"statement_id":"eventbridge-daily","principal":"events.amazonaws.com","source_arn":"arn:aws:events:us-east-1:111122223333:rule/NEW"}]'
  with_policy '{"Statement":[{"Sid":"np-ext-eventbridge-daily","Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"lambda:InvokeFunction","Condition":{"ArnLike":{"AWS:SourceArn":"arn:aws:events:us-east-1:111122223333:rule/OLD"}}}]}'

  run_sourced

  assert_success
  assert_aws_cli_called "remove-permission"
  assert_aws_cli_called "--source-arn arn:aws:events:us-east-1:111122223333:rule/NEW"
}

@test "sync_invoke_permissions: removes a managed permission that is no longer declared" {
  context_with '[]'
  with_policy '{"Statement":[{"Sid":"np-ext-stale","Effect":"Allow","Principal":{"Service":"s3.amazonaws.com"},"Action":"lambda:InvokeFunction"}]}'

  run_sourced

  assert_success
  assert_aws_cli_called "--statement-id np-ext-stale"
  assert_aws_cli_called "remove-permission"
}

@test "sync_invoke_permissions: never touches the scope's own API Gateway or ALB statements" {
  context_with '[]'
  with_policy '{"Statement":[{"Sid":"AllowAPIGatewayInvoke","Effect":"Allow","Principal":{"Service":"apigateway.amazonaws.com"},"Action":"lambda:InvokeFunction"},{"Sid":"AllowALBInvoke","Effect":"Allow","Principal":{"Service":"elasticloadbalancing.amazonaws.com"},"Action":"lambda:InvokeFunction"}]}'

  run_sourced

  assert_success
  assert_aws_cli_not_called "remove-permission"
}

@test "sync_invoke_permissions: leaves unrelated hand-made statements alone" {
  context_with '[]'
  with_policy '{"Statement":[{"Sid":"SomebodyElsesGrant","Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"lambda:InvokeFunction"}]}'

  run_sourced

  assert_success
  assert_aws_cli_not_called "remove-permission"
}

@test "sync_invoke_permissions: rejects a statement_id with invalid characters" {
  context_with '[{"statement_id":"arn:aws:events:us-east-1:1:rule/x","principal":"events.amazonaws.com"}]'
  no_policy

  run_sourced

  assert_failure
  assert_output_contains "Invalid statement_id"
  assert_aws_cli_not_called "add-permission"
}

@test "sync_invoke_permissions: rejects an entry missing its principal" {
  context_with '[{"statement_id":"no-principal"}]'
  no_policy

  run_sourced

  assert_failure
  assert_output_contains "missing 'statement_id' or 'principal'"
}

@test "sync_invoke_permissions: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  context_with '[]'

  run_sourced

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "sync_invoke_permissions: surfaces an AWS failure when adding a permission" {
  context_with '[{"statement_id":"eventbridge-daily","principal":"events.amazonaws.com"}]'
  no_policy
  aws_mock_response "lambda add-permission" 254 "AccessDeniedException"

  run_sourced

  assert_failure
  assert_output_contains "Failed to add invoke permission"
}
