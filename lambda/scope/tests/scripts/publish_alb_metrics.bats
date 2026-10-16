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
  unset ALB_ARN ALB_METRICS_PUBLISH_ENABLED ALB_METRICS_PUBLISH_TARGET DATADOG_API_KEY
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

create_curl_mock() {
  cat > "$MOCK_BIN_DIR/curl" << MOCK_SCRIPT
#!/bin/bash
printf '%s\n' "\$*" >> "$MOCK_BIN_DIR/curl_calls"
echo "${1:-202}"
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/curl"
}

@test "publish_alb_metrics: publishes the rule and target group counts of the scope's ALB" {
  export ALB_ARN="$LB_A"

  run run_publish

  assert_success
  assert_aws_call_contains '--namespace nullplatform/ApplicationELB'
  assert_aws_call_contains '{"MetricName":"RuleCount","Value":42,"Unit":"Count","Dimensions":[{"Name":"ALBName","Value":"alb-a"}]}'
  assert_aws_call_contains '{"MetricName":"TargetGroupCount","Value":42,"Unit":"Count","Dimensions":[{"Name":"ALBName","Value":"alb-a"}]}'
}

@test "publish_alb_metrics: also refreshes the ALB the scope moved away from" {
  export ALB_ARN="$LB_A"
  create_nrn_mock "$(jq -nc --arg a "$LB_B" '{namespaces: {lambda: {alb_arn: $a}}}')"

  run run_publish

  assert_success
  [ "$(metric_calls | wc -l | tr -d ' ')" = "2" ]
  assert_aws_call_contains '{"MetricName":"RuleCount","Value":7,"Unit":"Count","Dimensions":[{"Name":"ALBName","Value":"alb-b"}]}'
}

@test "publish_alb_metrics: on delete, reads the ALB from NRN metadata" {
  create_nrn_mock "$(jq -nc --arg a "$LB_B" '{namespaces: {lambda: {alb_arn: $a}}}')"

  run run_publish

  assert_success
  assert_aws_call_contains '"Value":7'
}

@test "publish_alb_metrics: skips scopes without an ALB" {
  run run_publish

  assert_success
  [ -z "$(metric_calls)" ]
}

@test "publish_alb_metrics: disabled from scope-configurations with a boolean false" {
  export ALB_ARN="$LB_A"
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_metrics_enabled":false}}}}'

  run run_publish

  assert_success
  [ -z "$(metric_calls)" ]
}

@test "publish_alb_metrics: disabled from the agent env" {
  export ALB_ARN="$LB_A"
  export ALB_METRICS_PUBLISH_ENABLED="false"

  run run_publish

  assert_success
  [ -z "$(metric_calls)" ]
}

@test "publish_alb_metrics: publishes to Datadog when that is the target" {
  export ALB_ARN="$LB_A"
  export ALB_METRICS_PUBLISH_TARGET="datadog" DATADOG_API_KEY="dd-key" AWS_REGION="us-east-1"
  create_curl_mock 202

  run run_publish

  assert_success
  [ -z "$(metric_calls)" ]
  grep -qF 'https://api.datadoghq.com/api/v2/series' "$MOCK_BIN_DIR/curl_calls"
  grep -qF '"metric":"nullplatform.applicationelb.rule_count","type":3,"points":[{"timestamp":' "$MOCK_BIN_DIR/curl_calls"
  grep -qF '"tags":["alb_name:alb-a","region:us-east-1"]' "$MOCK_BIN_DIR/curl_calls"
  assert_output_contains "alb-a rules=42 target_groups=42"
}

@test "publish_alb_metrics: a Datadog failure does not fail the workflow" {
  export ALB_ARN="$LB_A"
  export ALB_METRICS_PUBLISH_TARGET="datadog" DATADOG_API_KEY="dd-key"
  create_curl_mock 403

  run run_publish

  assert_success
  assert_output_contains "Failed to publish ALB metrics for alb-a to datadog"
}

@test "publish_alb_metrics: an unknown target reads nothing from AWS" {
  export ALB_ARN="$LB_A"
  export ALB_METRICS_PUBLISH_TARGET="cloudwach"

  run run_publish

  assert_success
  assert_output_contains "Unknown ALB metrics target 'cloudwach'"
  [ ! -s "$MOCK_BIN_DIR/aws_calls" ]
}

@test "publish_alb_metrics: a CloudWatch failure does not fail the workflow" {
  export ALB_ARN="$LB_A"
  mock_cloudwatch_failure

  run run_publish

  assert_success
  assert_output_contains "Failed to publish ALB metrics for alb-a to cloudwatch"
}

@test "publish_alb_metrics: still publishes the rule count when target groups cannot be read" {
  export ALB_ARN="$LB_A"
  rm "$MOCK_BIN_DIR"/alb/tgs_*

  run run_publish

  assert_success
  assert_aws_call_contains '"MetricName":"RuleCount","Value":42'
  run bash -c "grep -qF TargetGroupCount '$MOCK_BIN_DIR/aws_calls'"
  assert_failure
}

@test "publish_alb_metrics: skips an ALB whose rules cannot be read" {
  export ALB_ARN="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/unknown/zzz"

  run run_publish

  assert_success
  assert_output_contains "Could not count rules"
  [ -z "$(metric_calls)" ]
}
