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
  NEW_LB="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/np-lambda-private-3/new"
  NEW_LISTENER="arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/np-lambda-private-3/new/l443"
  mock_alb "$LB_A" "$LISTENER_A" 80
  mock_alb "$LB_B" "$LISTENER_B" 90

  export NETWORKING_MODE="alb"
  export VISIBILITY="private"
  export SCOPE_DOMAIN="ns-app-api.example.com"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export CONTEXT='{}'
  export ALB_PRIVATE_LISTENER_ARNS="$LISTENER_A,$LISTENER_B"
  export ALB_AUTOCREATE_ENABLED="true"
  unset ALB_LISTENER_RULE_CAPACITY ALB_LISTENER_RULE_ALERT_THRESHOLD ALB_LISTENER_RULE_PRIORITY_START ALB_AUTOCREATE_NAME_PREFIX
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_select_alb() {
  source "$LAMBDA_DIR/scope/scripts/select_alb" || return $?
  echo "RESULT listener=$ALB_LISTENER_ARN priority=$ALB_RULE_PRIORITY new=$ALB_RULE_IS_NEW"
  echo "RESULT alb=$ALB_ARN dns=$ALB_DNS_NAME"
}

pool_provider() {
  mock_providers "$(jq -nc --arg a "$LISTENER_A" --arg b "$LISTENER_B" '{results: [
    {id: "org-conf", category: "scope-configurations", attributes: {state: {}}},
    {id: "acc-conf", category: "scope-configurations", attributes: {networking: {alb_private_listener_arns: [$a, $b]}}}]}')"
}

aws_calls_with() {
  grep -F -- "$1" "$MOCK_BIN_DIR/aws_calls" || true
}

@test "autocreate_alb: off by default, a full pool still fails" {
  unset ALB_AUTOCREATE_ENABLED

  run run_select_alb

  assert_failure
  assert_output_contains "Every private ALB has 75 or more listener rules"
  assert_output_contains "networking.alb_autocreate_enabled = true"
  [ -z "$(aws_calls_with create-load-balancer)" ]
}

@test "autocreate_alb: a pool with room does not create an ALB" {
  mock_alb "$LB_B" "$LISTENER_B" 10

  run run_select_alb

  assert_success
  assert_line "RESULT listener=$LISTENER_B priority=100 new=true"
  [ -z "$(aws_calls_with create-load-balancer)" ]
}

@test "autocreate_alb: clones the first pool ALB when every ALB is full" {
  pool_provider

  run run_select_alb

  assert_success
  assert_output_contains "Every private ALB is full - creating np-lambda-private-3 from alb-a"
  assert_aws_call_contains '"Name":"np-lambda-private-3","Type":"application","Scheme":"internal","IpAddressType":"ipv4","Subnets":["subnet-1","subnet-2"],"SecurityGroups":["sg-1"],"Tags":[{"Key":"nullplatform:lambda-autocreated","Value":"private"}]'
  assert_aws_call_contains "modify-load-balancer-attributes --load-balancer-arn $NEW_LB"
  assert_aws_call_contains '"Protocol":"HTTPS","Port":443,"SslPolicy":"ELBSecurityPolicy-2016-08","Certificates":[{"CertificateArn":"arn:aws:acm:us-east-1:111122223333:certificate/wild"}]'
  assert_line "RESULT listener=$NEW_LISTENER priority=100 new=true"
  assert_line "RESULT alb=$NEW_LB dns=dns-np-lambda-private-3.elb.amazonaws.com"
}

@test "autocreate_alb: registers the new listener in the provider that holds the pool" {
  pool_provider

  run run_select_alb

  assert_success
  grep -qF "provider patch --id acc-conf --body {\"attributes\":{\"networking\":{\"alb_private_listener_arns\":[\"$LISTENER_A\",\"$LISTENER_B\",\"$NEW_LISTENER\"]}}}" "$MOCK_BIN_DIR/np_calls"
}

@test "autocreate_alb: seeds the provider list from the pool when it has none" {
  mock_providers '{"results":[{"id":"acc-conf","category":"scope-configurations","attributes":{}}]}'

  run run_select_alb

  assert_success
  grep -qF "\"alb_private_listener_arns\":[\"$LISTENER_A\",\"$LISTENER_B\",\"$NEW_LISTENER\"]" "$MOCK_BIN_DIR/np_calls"
}

@test "autocreate_alb: without a scope-configurations provider it warns and goes on" {
  run run_select_alb

  assert_success
  assert_output_contains "No scope-configurations provider to register $NEW_LISTENER in"
  assert_line "RESULT listener=$NEW_LISTENER priority=100 new=true"
}

@test "autocreate_alb: enabled from scope-configurations" {
  unset ALB_AUTOCREATE_ENABLED
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_autocreate_enabled":true}}}}'

  run run_select_alb

  assert_success
  assert_line "RESULT listener=$NEW_LISTENER priority=100 new=true"
}

@test "autocreate_alb: a provider false beats the agent env" {
  export CONTEXT='{"providers":{"scope-configurations":{"networking":{"alb_autocreate_enabled":false}}}}'

  run run_select_alb

  assert_failure
  [ -z "$(aws_calls_with create-load-balancer)" ]
}

@test "autocreate_alb: reuses an ALB it created that is not registered yet" {
  mock_existing_alb_name "np-lambda-private-3" "$NEW_LB" "private"
  mock_alb "$NEW_LB" "$NEW_LISTENER" 5

  run run_select_alb

  assert_success
  assert_output_contains "Reusing autocreated ALB np-lambda-private-3"
  [ -z "$(aws_calls_with create-load-balancer)" ]
  assert_line "RESULT listener=$NEW_LISTENER priority=100 new=true"
}

@test "autocreate_alb: skips names taken by other or full ALBs" {
  mock_existing_alb_name "np-lambda-private-3" "arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/np-lambda-private-3/other"
  mock_existing_alb_name "np-lambda-private-4" "$LB_A" "private"

  run run_select_alb

  assert_success
  assert_aws_call_contains '"Name":"np-lambda-private-5"'
}

@test "autocreate_alb: clones redirect listeners and copies extra certificates" {
  ALB_MOCK_LISTENER_DEFAULTS='{"Port":80,"Protocol":"HTTP","DefaultActions":[{"Type":"redirect","Order":1,"RedirectConfig":{"Protocol":"HTTPS","Port":"443","StatusCode":"HTTP_301"}}]}' \
    mock_alb "$LB_A" "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l80" 0
  mock_listener_certificates "$LISTENER_A" "arn:aws:acm:us-east-1:111122223333:certificate/extra"

  run run_select_alb

  assert_success
  assert_aws_call_contains '"Protocol":"HTTP","Port":80,"DefaultActions":[{"Type":"redirect","Order":1,"RedirectConfig":{"Protocol":"HTTPS","Port":"443","StatusCode":"HTTP_301"}}]'
  assert_aws_call_contains "add-listener-certificates --listener-arn $NEW_LISTENER --certificates [{\"CertificateArn\":\"arn:aws:acm:us-east-1:111122223333:certificate/extra\"}]"
}

@test "autocreate_alb: a forward default becomes a 404, other forward listeners are skipped" {
  forward='{"Port":443,"Protocol":"HTTPS","Certificates":[{"CertificateArn":"arn:cert"}],"DefaultActions":[{"Type":"forward","TargetGroupArn":"arn:tg"}]}'
  ALB_MOCK_LISTENER_DEFAULTS="$forward" mock_alb "$LB_A" "$LISTENER_A" 80
  ALB_MOCK_LISTENER_DEFAULTS="${forward/443/8443}" mock_alb "$LB_A" "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/alb-a/aaa/l8443" 0

  run run_select_alb

  assert_success
  assert_aws_call_contains '"DefaultActions":[{"Type":"fixed-response","FixedResponseConfig":{"StatusCode":"404","ContentType":"text/plain"}}]'
  assert_output_contains "Skipping listener :8443"
  [ -z "$(aws_calls_with '"Port":8443')" ]
}

@test "autocreate_alb: a failed create stops the workflow" {
  mock_create_lb_failure

  run run_select_alb

  assert_failure
  assert_output_contains "Failed to autocreate a private ALB: TooManyLoadBalancers"
}

@test "autocreate_alb: rejects a name prefix that does not fit an ALB name" {
  export ALB_AUTOCREATE_NAME_PREFIX="Bad_Prefix"

  run run_select_alb

  assert_failure
  assert_output_contains "ALB_AUTOCREATE_NAME_PREFIX must match"
}
