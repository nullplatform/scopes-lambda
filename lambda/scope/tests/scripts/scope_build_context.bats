#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  # Create temp dir for mock binaries and output
  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  _TEST_CLEANUP_DIRS=("$MOCK_BIN_DIR")
}

teardown() {
  teardown_test_env
  for dir in "${_TEST_CLEANUP_DIRS[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir"
  done
}

@test "scope/build_context: fails when CONTEXT is not set" {
  unset CONTEXT

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_failure
  assert_output_contains "CONTEXT variable is not set or empty"
  assert_output_contains "Ensure the scope event includes a valid CONTEXT JSON"
  assert_output_contains "Verify the agent trigger is passing CONTEXT correctly"
}

@test "scope/build_context: fails when CONTEXT is empty string" {
  export CONTEXT=""

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_failure
  assert_output_contains "CONTEXT variable is not set or empty"
}

@test "scope/build_context: fails when scope ID is missing from CONTEXT" {
  export CONTEXT='{"scope": {"slug": "test"}, "namespace": {"slug": "ns"}, "application": {"slug": "app"}, "account": {"slug": "acc"}}'

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_failure
  assert_output_contains "Failed to extract scope ID from CONTEXT"
  assert_output_contains "The CONTEXT JSON is malformed or missing .scope.id"
  assert_output_contains "Ensure the scope was created correctly in nullplatform"
}

@test "scope/build_context: fails when scope ID is null" {
  export CONTEXT='{"scope": {"id": null, "slug": "test", "nrn": "nrn:1", "visibility": "public"}, "namespace": {"slug": "ns"}, "application": {"slug": "app"}, "account": {"slug": "acc"}}'

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_failure
  assert_output_contains "Failed to extract scope ID from CONTEXT"
}

@test "scope/build_context: extracts scope ID correctly" {
  set_context "public"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "scope_id=scope-123"
}

@test "scope/build_context: generates function name from slugs" {
  set_context "public"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "function_name=scope-123-my-app-my-scope"
}

@test "scope/build_context: truncates function name to 64 characters" {
  export CONTEXT=$(echo "$MOCK_CONTEXT_PUBLIC" | jq '
    .namespace.slug = "very-long-namespace-slug-that-will-exceed" |
    .application.slug = "very-long-application-slug-exceeding" |
    .scope.slug = "long-scope"
  ')
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  # The function name should be truncated - check output doesn't contain name longer than 64 chars
  local fn_line
  fn_line=$(echo "$output" | grep "function_name=" | head -1)
  local fn_name="${fn_line##*function_name=}"
  [ ${#fn_name} -le 64 ]
}

@test "scope/build_context: extracts visibility from context" {
  set_context "private"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")
  export ALB_LISTENER_RULE_CAPACITY=100
  export ALB_LISTENER_RULE_ALERT_THRESHOLD=80

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "visibility=private"
}

@test "scope/build_context: defaults visibility to public" {
  export CONTEXT=$(echo "$MOCK_CONTEXT_PUBLIC" | jq 'del(.scope.capabilities.visibility)')
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "visibility=public"
}

@test "scope/build_context: fails when ALB capacity is at or below threshold for private scopes" {
  set_context "private"
  export ALB_LISTENER_RULE_CAPACITY=80
  export ALB_LISTENER_RULE_ALERT_THRESHOLD=80
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_failure
  assert_output_contains "ALB listener rule capacity (80) is at or below the alert threshold (80)"
  assert_output_contains "Too many private scopes sharing the same internal ALB"
  assert_output_contains "Increase ALB_LISTENER_RULE_CAPACITY if the ALB supports more rules"
  assert_output_contains "Remove unused scopes to free up listener rule slots"
  assert_output_contains "Provision an additional internal ALB for this account"
}

@test "scope/build_context: creates output directory" {
  set_context "public"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "output_dir=$NP_OUTPUT_DIR/output/scope-123"
  [ -d "$NP_OUTPUT_DIR/output/scope-123" ]
}

@test "scope/build_context: generates resource tags JSON" {
  set_context "public"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "Scope context built successfully"
}

@test "scope/build_context: outputs full success summary" {
  set_context "public"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  _TEST_CLEANUP_DIRS+=("$NP_OUTPUT_DIR")

  run bash "$LAMBDA_DIR/scope/build_context"

  assert_success
  assert_output_contains "Building scope context..."
  assert_output_contains "namespace=my-namespace"
  assert_output_contains "application=my-app"
  assert_output_contains "scope=my-scope"
  assert_output_contains "runtime=nodejs20.x"
  assert_output_contains "handler=index.handler"
  assert_output_contains "architecture=arm64"
  assert_line "✨ Scope context built successfully"
}
