#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  export SCOPE_ID="scope-1"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/out"
  export NETWORKING_MODE="alb"
  export VISIBILITY="private"
  export ALB_PRIVATE_LISTENER_ARNS="arn:listener-a"
  export ALB_PUBLIC_LISTENER_ARNS=""
}

teardown() {
  teardown_test_env
}

run_networking_context() {
  source "$LAMBDA_DIR/scope/tofu/networking/build_context" || return $?
  echo "RESULT mode=$NETWORKING_MODE key=$TOFU_INIT_VARIABLES dir=$TF_WORKING_DIR"
}

@test "networking/build_context: keeps networking in its own state" {
  run run_networking_context

  assert_success
  assert_line "RESULT mode=alb key=-backend-config=key=lambda/scope-1/networking.tfstate dir=$OUTPUT_DIR/terraform-networking"
}

@test "networking/build_context: no listener for the visibility means no HTTP exposure" {
  export VISIBILITY="public"

  run run_networking_context

  assert_success
  assert_output_contains "No load_balancer.public listener configured - the scope gets no HTTP exposure"
  assert_output_contains "RESULT mode=none"
}

@test "networking/build_context: API Gateway does not need listeners" {
  export NETWORKING_MODE="api_gateway"
  export VISIBILITY="public"

  run run_networking_context

  assert_success
  assert_output_contains "RESULT mode=api_gateway"
}

@test "networking/build_context: drops modules left by a previous run" {
  mkdir -p "$OUTPUT_DIR/terraform-networking"
  touch "$OUTPUT_DIR/terraform-networking/networking_alb_main.tf"

  run run_networking_context

  assert_success
  [ ! -f "$OUTPUT_DIR/terraform-networking/networking_alb_main.tf" ]
}
