#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/alb_mock.bash"

  setup_test_env

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_alb_mock
  create_nrn_mock '{}'

  # SERVICE_PATH with the real utils and the real script, but a fake do_tofu.
  export SERVICE_PATH="$MOCK_BIN_DIR/service"
  mkdir -p "$SERVICE_PATH/scope/tofu" "$SERVICE_PATH/scope/scripts"
  ln -s "$LAMBDA_DIR/utils" "$SERVICE_PATH/utils"
  ln -s "$LAMBDA_DIR/scope/scripts/apply_networking" "$SERVICE_PATH/scope/scripts/apply_networking"
  : > "$MOCK_BIN_DIR/tofu_runs"
  cat > "$SERVICE_PATH/scope/tofu/do_tofu" << 'FAKE'
#!/bin/bash
# Each run pops the next "<exit> <message>" line from tofu_results (default: success).
mock_dir="$(cd "$(dirname "$0")/../../.." && pwd)"
echo "$TOFU_ACTION priority=$(echo "$TOFU_VARIABLES" | jq -r '.alb_rule_priority // empty')" >> "$mock_dir/tofu_runs"
result=$(head -1 "$mock_dir/tofu_results" 2>/dev/null)
sed -i.bak '1d' "$mock_dir/tofu_results" 2>/dev/null
code="${result%% *}"
echo "${result#* }"
[ -f "$mock_dir/tofu_outputs" ] && cp "$mock_dir/tofu_outputs" "$TF_WORKING_DIR/outputs.json"
exit "${code:-0}"
FAKE
  chmod +x "$SERVICE_PATH/scope/tofu/do_tofu"

  LB_A="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/alb-a/aaa"
  LISTENER_A="arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l1"
  mock_alb "$LB_A" "$LISTENER_A" 10

  export TF_WORKING_DIR="$BATS_TEST_TMPDIR/tf"
  mkdir -p "$TF_WORKING_DIR"
  export NETWORKING_MODE="alb"
  export VISIBILITY="private"
  export SCOPE_ID="scope-1"
  export SCOPE_DOMAIN="ns-app-api.example.com"
  export ALB_ARN="$LB_A"
  export ALB_LISTENER_ARN="$LISTENER_A"
  export ALB_RULE_PRIORITY=100
  export ALB_RULE_IS_NEW="true"
  export ALB_LISTENER_RULE_CAPACITY=98
  export ALB_LISTENER_RULE_PRIORITY_START=100
  export TOFU_VARIABLES='{"alb_rule_priority":100}'
  export TOFU_STATE_BUCKET="np-state"
  export STATE_KEY="lambda/scope-1/networking.tfstate"
  export AWS_REGION="us-east-1"
  unset TOFU_ACTION
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_apply_networking() {
  source "$SERVICE_PATH/scope/scripts/apply_networking" || return $?
  echo "RESULT priority=$ALB_RULE_PRIORITY"
}

tofu_results() {
  printf '%s\n' "$@" > "$MOCK_BIN_DIR/tofu_results"
}

tofu_runs() {
  cat "$MOCK_BIN_DIR/tofu_runs"
}

@test "apply_networking: applies and publishes the scope domain" {
  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "apply priority=100" ]
  grep -qF 'scope patch --id scope-1 --body {"domain":"ns-app-api.example.com"}' "$MOCK_BIN_DIR/np_calls"
}

@test "apply_networking: retries with a fresh priority when it was taken concurrently" {
  mock_scope_rule "$LISTENER_A" "concurrent.example.com" 100
  tofu_results "1 Error: PriorityInUse: Priority '100' is currently in use" "0 ok"

  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "$(printf 'apply priority=100\napply priority=101')" ]
  assert_output_contains "retrying with 101 (attempt 2/3)"
  assert_line "RESULT priority=101"
}

@test "apply_networking: gives up after three priority conflicts" {
  tofu_results "1 PriorityInUse" "1 PriorityInUse" "1 PriorityInUse" "0 ok"

  run run_apply_networking

  assert_failure
  [ "$(tofu_runs | wc -l | tr -d ' ')" = "3" ]
  assert_output_contains "Networking tofu apply failed"
}

@test "apply_networking: does not retry other failures" {
  tofu_results "1 Error: AccessDenied"

  run run_apply_networking

  assert_failure
  [ "$(tofu_runs | wc -l | tr -d ' ')" = "1" ]
}

@test "apply_networking: refuses a new rule on an ALB at the hard cap" {
  mock_alb "$LB_A" "$LISTENER_A" 98

  run run_apply_networking

  assert_failure
  assert_output_contains "has 98 listener rules, at or above the cap of 98"
  [ ! -s "$MOCK_BIN_DIR/tofu_runs" ]
}

@test "apply_networking: an existing rule is re-applied even at the hard cap" {
  mock_alb "$LB_A" "$LISTENER_A" 98
  export ALB_RULE_IS_NEW="false"

  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "apply priority=100" ]
}

@test "apply_networking: destroys on delete without touching the domain" {
  export TOFU_ACTION="destroy"
  export ALB_RULE_IS_NEW="false"

  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "destroy priority=100" ]
  ! grep -q "scope patch" "$MOCK_BIN_DIR/np_calls"
}

@test "apply_networking: publishes the execute-api host without a custom domain" {
  export NETWORKING_MODE="api_gateway"
  export ALB_RULE_IS_NEW="false"
  export API_GATEWAY_CUSTOM_DOMAIN=""
  echo '{"api_gateway_endpoint":{"value":"https://abc123.execute-api.us-east-1.amazonaws.com"}}' > "$MOCK_BIN_DIR/tofu_outputs"

  run run_apply_networking

  assert_success
  grep -qF '{"domain":"abc123.execute-api.us-east-1.amazonaws.com"}' "$MOCK_BIN_DIR/np_calls"
}

@test "apply_networking: leaves the domain alone without HTTP exposure" {
  export NETWORKING_MODE="none"
  export ALB_RULE_IS_NEW="false"

  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "apply priority=100" ]
  ! grep -q "scope patch" "$MOCK_BIN_DIR/np_calls"
}

@test "apply_networking: fails when the scope domain cannot be set" {
  touch "$MOCK_BIN_DIR/np_fails"

  run run_apply_networking

  assert_failure
  assert_output_contains "Failed to update the scope domain"
}

@test "apply_networking: skips tofu when there is no networking state to empty" {
  export NETWORKING_MODE="none"
  export ALB_RULE_IS_NEW="false"
  mock_s3_head_error "An error occurred (404) when calling the HeadObject operation: Not Found"

  run run_apply_networking

  assert_success
  assert_output_contains "No networking state - nothing to remove"
  [ ! -s "$MOCK_BIN_DIR/tofu_runs" ]
  assert_aws_call_contains "s3api head-object --bucket np-state --key lambda/scope-1/networking.tfstate --region us-east-1"
}

@test "apply_networking: skips the destroy of a scope that never had networking" {
  export TOFU_ACTION="destroy"
  export ALB_RULE_IS_NEW="false"
  mock_s3_head_error "An error occurred (404) when calling the HeadObject operation: Not Found"

  run run_apply_networking

  assert_success
  [ ! -s "$MOCK_BIN_DIR/tofu_runs" ]
}

@test "apply_networking: still destroys when the state cannot be checked" {
  export TOFU_ACTION="destroy"
  export ALB_RULE_IS_NEW="false"
  mock_s3_head_error "An error occurred (403) when calling the HeadObject operation: Forbidden"

  run run_apply_networking

  assert_success
  [ "$(tofu_runs)" = "destroy priority=100" ]
}
