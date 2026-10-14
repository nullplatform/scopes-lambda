#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  # tofu (and mise, when the runner has it) record their calls instead of touching state.
  : > "$MOCK_BIN_DIR/tofu_calls"
  cat > "$MOCK_BIN_DIR/tofu" << 'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$(dirname "$0")/tofu_calls"
[ -f "$(dirname "$0")/tofu_fails" ] && [[ "$*" == *"state rm"* ]] && exit 1
exit 0
MOCK
  cat > "$MOCK_BIN_DIR/mise" << 'MOCK'
#!/bin/bash
shift 3
exec "$(dirname "$0")/tofu" "$@"
MOCK
  chmod +x "$MOCK_BIN_DIR/tofu" "$MOCK_BIN_DIR/mise"

  export SCOPE_ID="223816164"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/out"
  export TOFU_STATE_BUCKET="np-state"
  export AWS_REGION="us-east-1"
  export NETWORKING_MODE="alb"
  export VISIBILITY="public"
  export ALB_PUBLIC_LISTENER_ARNS="arn:listener-public"
  export ALB_PRIVATE_LISTENER_ARNS=""
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_handover() {
  source "$LAMBDA_DIR/scope/scripts/handover_networking_state"
}

legacy_state() {
  aws_mock_response "s3 cp" 0 '{"resources":[
    {"mode":"data","type":"aws_lb","name":"main"},
    {"mode":"managed","type":"aws_lambda_function","name":"main"},
    {"mode":"managed","type":"aws_lb_listener_rule","name":"lambda"},
    {"mode":"managed","type":"aws_lb_target_group","name":"lambda"},
    {"mode":"managed","type":"aws_lb_target_group_attachment","name":"lambda"},
    {"mode":"managed","type":"aws_lambda_permission","name":"alb"},
    {"mode":"managed","type":"aws_route53_record","name":"alb"}]}'
}

@test "handover_networking_state: removes the ALB resources from the main state" {
  legacy_state

  run run_handover

  assert_success
  grep -qF -- "-backend-config=key=lambda/223816164/terraform.tfstate" "$MOCK_BIN_DIR/tofu_calls"
  grep -qF "state rm aws_lb_listener_rule.lambda aws_lb_target_group.lambda aws_lb_target_group_attachment.lambda aws_lambda_permission.alb aws_route53_record.alb" "$MOCK_BIN_DIR/tofu_calls"
  ! grep -q "aws_lambda_function" "$MOCK_BIN_DIR/tofu_calls"
}

@test "handover_networking_state: leaves a state without networking alone" {
  aws_mock_response "s3 cp" 0 '{"resources":[{"mode":"managed","type":"aws_lambda_function","name":"main"}]}'

  run run_handover

  assert_success
  [ ! -s "$MOCK_BIN_DIR/tofu_calls" ]
}

@test "handover_networking_state: does nothing for a scope without a main state" {
  aws_mock_response "s3 cp" 1 'NoSuchKey'

  run run_handover

  assert_success
  [ ! -s "$MOCK_BIN_DIR/tofu_calls" ]
}

@test "handover_networking_state: keeps the resources when no ALB stack will take them" {
  legacy_state
  export ALB_PUBLIC_LISTENER_ARNS=""

  run run_handover

  assert_success
  [ ! -s "$MOCK_BIN_DIR/tofu_calls" ]
  assert_aws_cli_not_called "s3 cp"
}

@test "handover_networking_state: stops the workflow when the state cannot be changed" {
  legacy_state
  touch "$MOCK_BIN_DIR/tofu_fails"

  run run_handover

  assert_failure
  assert_output_contains "The main stack would destroy them on its next apply"
}
