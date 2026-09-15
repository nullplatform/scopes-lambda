#!/usr/bin/env bats
# Guards that must behave differently per lifecycle phase, plus steps that must fail
# without killing the worker. Scripts are sourced here, as the engine does.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  TMP_DIR="$(mktemp -d)"
  export NP_OUTPUT_DIR="$TMP_DIR"

  PROVIDERS_JSON='{"results":[{"category":"cloud-providers","attributes":{"account":{"id":"111122223333","region":"us-east-1"}}},{"category":"scope-configurations","attributes":{"state":{"tofu_state_bucket":"np-state"}}}]}'

  # Private scope: the visibility that triggers the ALB capacity guard.
  export CONTEXT='{"scope":{"id":"scope-1","slug":"api","nrn":"organization=1:account=2:namespace=3:application=4:scope=5","capabilities":{"visibility":"private","architecture":"arm64","deployment_type":"docker-image"}},"namespace":{"slug":"ns"},"application":{"slug":"app"},"account":{"slug":"acc"}}'

  # Capacity below the alert threshold — the condition that trips the guard.
  export ALB_LISTENER_RULE_CAPACITY="50"
  export ALB_LISTENER_RULE_ALERT_THRESHOLD="80"
}

teardown() {
  rm -rf "$TMP_DIR"
  teardown_test_env
}

run_build_context() {
  source "$LAMBDA_DIR/scope/build_context"
}

run_fetch_scope_configuration() {
  source "$LAMBDA_DIR/utils/log"
  source "$LAMBDA_DIR/utils/fetch_scope_configuration"
}

# The marker only prints if the step returned; `exit` would kill the subshell first.
run_assume_role_step() {
  source "$LAMBDA_DIR/utils/assume_role_step"
  local rc=$?
  echo "STEP_RETURNED_${rc}_CALLER_ALIVE"
  return $rc
}

@test "build_context: ALB capacity guard does not block a destroy" {
  mock_np "$PROVIDERS_JSON"
  export TOFU_ACTION="destroy"

  run run_build_context

  assert_success
  assert_output_contains "Scope context built successfully"
  assert_output_not_contains "ALB listener rule capacity"
}

@test "build_context: ALB capacity guard still blocks an apply" {
  mock_np "$PROVIDERS_JSON"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_failure
  assert_output_contains "ALB listener rule capacity"
}

@test "build_context: ALB capacity guard applies when TOFU_ACTION is unset" {
  mock_np "$PROVIDERS_JSON"
  unset TOFU_ACTION

  run run_build_context

  assert_failure
  assert_output_contains "ALB listener rule capacity"
}

@test "fetch_scope_configuration: surfaces an np failure instead of an empty config" {
  mock_np_error "connection refused talking to the nullplatform API"

  run run_fetch_scope_configuration

  assert_failure
  assert_output_contains "Failed to fetch providers"
  assert_output_contains "connection refused"
  assert_output_not_contains "Scope configuration fetched successfully"
}

# Proves the `return N 2>/dev/null || exit N` idiom: sourced it returns, executed it exits.
@test "assume_role_step: still fails non-zero when executed instead of sourced" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda"

  run bash "$LAMBDA_DIR/utils/assume_role_step"

  assert_failure
  assert_output_contains "assume_role step failed"
}

@test "assume_role_step: a failed assume-role returns instead of killing the worker" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda"
  mock_aws_error "AccessDenied: User is not authorized to perform sts:AssumeRole"

  run run_assume_role_step

  assert_failure
  assert_output_contains "assume_role step failed"
  assert_output_contains "STEP_RETURNED_1_CALLER_ALIVE"
}
