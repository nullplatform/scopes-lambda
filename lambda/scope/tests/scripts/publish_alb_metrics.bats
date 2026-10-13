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
  mock_alb "$LB_A" "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l1" 42
  mock_alb "$LB_B" "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-b/bbb/l1" 7

  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export VISIBILITY="private"
  unset ALB_ARN
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_publish() {
  source "$LAMBDA_DIR/scope/scripts/publish_alb_metrics"
}

metric_calls() {
  grep "cloudwatch put-metric-data" "$MOCK_BIN_DIR/aws_calls" || true
}

@test "publish_alb_metrics: publishes the rule count of the scope's ALB" {
  export ALB_ARN="$LB_A"

  run run_publish

  assert_success
  assert_aws_call_contains '--namespace Nullplatform/Lambda'
  assert_aws_call_contains '"MetricName":"ListenerRuleCount","Unit":"Count","Value":42'
  assert_aws_call_contains '{"Name":"LoadBalancer","Value":"app/alb-a/aaa"},{"Name":"Visibility","Value":"private"}'
}

@test "publish_alb_metrics: also refreshes the ALB the scope moved away from" {
  export ALB_ARN="$LB_A"
  create_nrn_mock "$(jq -nc --arg a "$LB_B" '{namespaces: {lambda: {alb_arn: $a, alb_visibility: "public"}}}')"

  run run_publish

  assert_success
  [ "$(metric_calls | wc -l | tr -d ' ')" = "2" ]
  assert_aws_call_contains '"Value":7,"Dimensions":[{"Name":"LoadBalancer","Value":"app/alb-b/bbb"},{"Name":"Visibility","Value":"public"}]'
}

@test "publish_alb_metrics: on delete, reads the ALB from NRN metadata" {
  create_nrn_mock "$(jq -nc --arg a "$LB_B" '{namespaces: {lambda: {alb_arn: $a, alb_visibility: "private"}}}')"

  run run_publish

  assert_success
  assert_aws_call_contains '"Value":7'
}

@test "publish_alb_metrics: skips scopes without an ALB" {
  run run_publish

  assert_success
  [ -z "$(metric_calls)" ]
}

@test "publish_alb_metrics: a CloudWatch failure does not fail the workflow" {
  export ALB_ARN="$LB_A"
  mock_cloudwatch_failure

  run run_publish

  assert_success
  assert_output_contains "Failed to publish ListenerRuleCount for app/alb-a/aaa"
}

@test "publish_alb_metrics: skips an ALB whose rules cannot be read" {
  export ALB_ARN="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/unknown/zzz"

  run run_publish

  assert_success
  assert_output_contains "Could not count rules"
  [ -z "$(metric_calls)" ]
}
