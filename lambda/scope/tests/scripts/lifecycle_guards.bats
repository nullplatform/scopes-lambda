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

# The marker would only print if the step returned; with `exit` it never runs.
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
  assert_line "🔍 Building scope context..."
  assert_line "📋 Function: scope-1-app-api | Visibility: private"
  assert_line "✨ Scope context built successfully"
  assert_output_not_contains "ALB listener rule capacity"
}

@test "build_context: ALB capacity guard still blocks an apply" {
  mock_np "$PROVIDERS_JSON"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_failure
  assert_line "❌ ALB listener rule capacity (50) is at or below the alert threshold (80)"
  assert_line "💡 Possible causes:"
  assert_line "   Too many private scopes sharing the same internal ALB"
  assert_line "   The ALB listener has a hard limit of rules per listener"
  assert_line "🔧 How to fix:"
  assert_line "   • Increase ALB_LISTENER_RULE_CAPACITY if the ALB supports more rules"
  assert_line "   • Remove unused scopes to free up listener rule slots"
  assert_line "   • Provision an additional internal ALB for this account"
  assert_output_not_contains "Scope context built successfully"
}

@test "build_context: ALB capacity guard applies when TOFU_ACTION is unset" {
  mock_np "$PROVIDERS_JSON"
  unset TOFU_ACTION

  run run_build_context

  assert_failure
  assert_line "❌ ALB listener rule capacity (50) is at or below the alert threshold (80)"
  assert_output_not_contains "Scope context built successfully"
}

@test "fetch_scope_configuration: surfaces an np failure instead of an empty config" {
  mock_np_error "connection refused talking to the nullplatform API"

  run run_fetch_scope_configuration

  assert_failure
  assert_line "🔑 Fetching scope configuration..."
  assert_line "❌ Failed to fetch providers for NRN=organization=1:account=2:namespace=3:application=4:scope=5"
  assert_line "💡 Possible causes:"
  assert_line "   - The nullplatform API is unreachable or returned an error"
  assert_line "   - The agent's API key lacks permission to list providers"
  assert_line "🔧 How to fix:"
  assert_line "   • Verify the agent can reach the nullplatform API"
  assert_line "   • Check the agent's credentials and NRN visibility"
  assert_line "   📋 Error: connection refused talking to the nullplatform API "
  assert_output_not_contains "Scope configuration fetched successfully"
}

@test "assume_role_step: a failed assume-role aborts the step" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda"
  mock_aws_error "AccessDenied: User is not authorized to perform sts:AssumeRole"

  run run_assume_role_step

  assert_failure
  assert_line "   🔑 Assuming role: arn:aws:iam::111122223333:role/np-lambda"
  assert_line "ERROR: sts:AssumeRole failed for arn:aws:iam::111122223333:role/np-lambda"
  assert_line "AccessDenied: User is not authorized to perform sts:AssumeRole"
  assert_line "❌ assume_role step failed: could not assume arn:aws:iam::111122223333:role/np-lambda"
  assert_line "💡 Possible causes:"
  assert_line "   - The agent's pod role is not allowed to sts:AssumeRole the target role"
  assert_line "   - The target role's trust policy does not trust the agent role"
  assert_line "   - The resolved ARN is wrong (check the IAM provider selector=lambda)"
  assert_output_not_contains "CALLER_ALIVE"
}
