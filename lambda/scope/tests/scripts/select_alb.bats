#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/alb_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_alb_mock
  create_nrn_mock '{}'

  LB_A="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/alb-a/aaa"
  LB_B="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/alb-b/bbb"
  LISTENER_A="arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l1"
  LISTENER_B="arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-b/bbb/l1"

  export NETWORKING_MODE="alb"
  export VISIBILITY="private"
  export SCOPE_DOMAIN="ns-app-api.example.com"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export CONTEXT='{}'
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_A,$LISTENER_B"
  export ALB_PUBLIC_LISTENER_ARNS=""
  unset ALB_LISTENER_RULE_CAPACITY ALB_LISTENER_RULE_ALERT_THRESHOLD ALB_LISTENER_RULE_PRIORITY_START
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

# The step returns at top level, so it is sourced as the engine does.
run_select_alb() {
  source "$LAMBDA_DIR/scope/scripts/select_alb" || return $?
  echo "RESULT listener=$ALB_LISTENER_ARN priority=$ALB_RULE_PRIORITY new=$ALB_RULE_IS_NEW"
  echo "RESULT alb=$ALB_ARN dns=$ALB_DNS_NAME zone=$ALB_ZONE_ID"
  echo "RESULT target_group=$ALB_TARGET_GROUP_NAME"
}

stored_assignment() {
  create_nrn_mock "$(jq -nc --arg l "$1" --arg v "$2" '{namespaces: {lambda: {alb_listener_arn: $l, alb_visibility: $v}}}')"
}

@test "select_alb: puts a new rule on the ALB with the fewest rules" {
  mock_alb "$LB_A" "$LISTENER_A" 40
  mock_alb "$LB_B" "$LISTENER_B" 10

  run run_select_alb

  assert_success
  assert_line "RESULT listener=$LISTENER_B priority=100 new=true"
  assert_line "RESULT alb=$LB_B dns=dns-alb-b.elb.amazonaws.com zone=ZALB"
}

@test "select_alb: counts the rules of every listener on the ALB" {
  mock_alb "$LB_A" "$LISTENER_A" 30
  mock_alb "$LB_A" "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l2" 30
  mock_alb "$LB_B" "$LISTENER_B" 50

  run run_select_alb

  assert_success
  assert_output_contains "listener=$LISTENER_B"
}

@test "select_alb: skips an ALB at the alert threshold" {
  mock_alb "$LB_A" "$LISTENER_A" 75
  mock_alb "$LB_B" "$LISTENER_B" 74

  run run_select_alb

  assert_success
  assert_output_contains "listener=$LISTENER_B"
}

@test "select_alb: fails when every ALB is at the alert threshold" {
  mock_alb "$LB_A" "$LISTENER_A" 75
  mock_alb "$LB_B" "$LISTENER_B" 90

  run run_select_alb

  assert_failure
  assert_output_contains "Every private ALB has 75 or more listener rules"
  assert_output_contains "Add another ALB listener to networking.alb_private_listener_arns (scope-configurations)"
}

@test "select_alb: the provider threshold wins over the environment" {
  export ALB_LISTENER_RULE_ALERT_THRESHOLD=75
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_listener_rule_alert_threshold":50}}}}'
  mock_alb "$LB_A" "$LISTENER_A" 60
  mock_alb "$LB_B" "$LISTENER_B" 70

  run run_select_alb

  assert_failure
  assert_output_contains "Every private ALB has 50 or more listener rules"
}

@test "select_alb: keeps the scope on its stored listener even past the threshold" {
  stored_assignment "$LISTENER_A" "private"
  mock_alb "$LB_A" "$LISTENER_A" 90
  mock_scope_rule "$LISTENER_A" "$SCOPE_DOMAIN" 140
  mock_alb "$LB_B" "$LISTENER_B" 0

  run run_select_alb

  assert_success
  assert_line "RESULT listener=$LISTENER_A priority=140 new=false"
  assert_output_not_contains "no longer configured"
}

@test "select_alb: keeps the scope on a listener removed from the configuration" {
  stored_assignment "$LISTENER_A" "private"
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_B"
  mock_alb "$LB_A" "$LISTENER_A" 20
  mock_scope_rule "$LISTENER_A" "$SCOPE_DOMAIN" 120
  mock_alb "$LB_B" "$LISTENER_B" 0

  run run_select_alb

  assert_success
  assert_output_contains "listener=$LISTENER_A priority=120 new=false"
  assert_output_contains "Listener $LISTENER_A is no longer configured - keeping the scope on it"
}

@test "select_alb: re-picks when the visibility changed" {
  stored_assignment "$LISTENER_A" "public"
  mock_alb "$LB_A" "$LISTENER_A" 20
  mock_scope_rule "$LISTENER_A" "$SCOPE_DOMAIN" 120
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_B"
  mock_alb "$LB_B" "$LISTENER_B" 5

  run run_select_alb

  assert_success
  assert_output_contains "listener=$LISTENER_B priority=100 new=true"
}

@test "select_alb: re-picks when the stored listener no longer exists" {
  stored_assignment "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/gone/ggg/l1" "private"
  mock_alb "$LB_A" "$LISTENER_A" 20
  mock_alb "$LB_B" "$LISTENER_B" 30

  run run_select_alb

  assert_success
  assert_output_contains "listener=$LISTENER_A priority=100 new=true"
}

@test "select_alb: re-adopts a rule found on a candidate when metadata is missing" {
  mock_alb "$LB_A" "$LISTENER_A" 10
  mock_alb "$LB_B" "$LISTENER_B" 50
  mock_scope_rule "$LISTENER_B" "$SCOPE_DOMAIN" 130

  run run_select_alb

  assert_success
  assert_line "RESULT listener=$LISTENER_B priority=130 new=false"
}

@test "select_alb: an existing rule keeps the target group it forwards to" {
  mock_alb "$LB_A" "$LISTENER_A" 10
  mock_scope_rule "$LISTENER_A" "$SCOPE_DOMAIN" 102 "223816164-lambdaand-lambdasco"
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_A"

  run run_select_alb

  assert_success
  assert_line "RESULT target_group=223816164-lambdaand-lambdasco"
}

@test "select_alb: a new rule leaves the target group name to the setup" {
  mock_alb "$LB_A" "$LISTENER_A" 10
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_A"

  run run_select_alb

  assert_success
  assert_line "RESULT target_group="
}

@test "select_alb: skips a configured listener that does not exist" {
  export ALB_PRIVATE_LISTENER_ARNS="arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/gone/ggg/l1,$LISTENER_B"
  mock_alb "$LB_B" "$LISTENER_B" 10

  run run_select_alb

  assert_success
  assert_output_contains "not found - skipping"
  assert_output_contains "listener=$LISTENER_B"
}

@test "select_alb: takes the lowest free priority from the start value" {
  export ALB_LISTENER_RULE_PRIORITY_START=3
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_A"
  mock_alb "$LB_A" "$LISTENER_A" 5

  run run_select_alb

  assert_success
  assert_output_contains "priority=6 new=true"
}

@test "select_alb: rejects an alert threshold not below the capacity" {
  export ALB_LISTENER_RULE_ALERT_THRESHOLD=98
  export ALB_LISTENER_RULE_CAPACITY=98

  run run_select_alb

  assert_failure
  assert_output_contains "Invalid ALB rule thresholds: alert=98 capacity=98"
}

@test "select_alb: rejects a capacity above the AWS cap" {
  export ALB_LISTENER_RULE_CAPACITY=120

  run run_select_alb

  assert_failure
  assert_output_contains "Invalid ALB rule thresholds"
}

@test "select_alb: fails when no listener is configured for the visibility" {
  export VISIBILITY="public"

  run run_select_alb

  assert_failure
  assert_output_contains "No ALB listener configured for public scopes"
}

@test "select_alb: fails instead of guessing when rules cannot be read" {
  mock_alb "$LB_A" "$LISTENER_A" 10
  rm -f "$MOCK_BIN_DIR"/alb/rules_*

  run run_select_alb

  assert_failure
  assert_output_contains "Failed to read ALB listener rules for $LISTENER_A"
}

@test "select_alb: does nothing outside ALB mode" {
  export NETWORKING_MODE="api_gateway"

  run run_select_alb

  assert_success
  assert_line "RESULT listener= priority= new="
  [ ! -s "$MOCK_BIN_DIR/aws_calls" ]
}
