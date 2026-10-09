#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  export AWS_REGION="us-west-2"
  export TOFU_STATE_BUCKET="np-state"
  unset TOFU_STATE_BUCKET_REGION
  export TOFU_VARIABLES='{}'
  export TOFU_INIT_VARIABLES=""
}

teardown() {
  teardown_test_env
}

run_provider_setup() {
  source "$LAMBDA_DIR/scope/tofu/provider/aws/setup"
  echo "INIT=$TOFU_INIT_VARIABLES"
  echo "PROVIDER_REGION=$(echo "$TOFU_VARIABLES" | jq -r '.aws_provider.region')"
}

@test "provider/aws/setup: backend region defaults to AWS_REGION" {
  run run_provider_setup

  assert_success
  assert_output_contains "-backend-config=region=us-west-2"
}

@test "provider/aws/setup: TOFU_STATE_BUCKET_REGION overrides only the backend region" {
  export TOFU_STATE_BUCKET_REGION="us-east-1"

  run run_provider_setup

  assert_success
  assert_output_contains "-backend-config=region=us-east-1"
  assert_output_not_contains "-backend-config=region=us-west-2"
  assert_line "PROVIDER_REGION=us-west-2"
}

@test "provider/aws/setup: fails when TOFU_STATE_BUCKET is missing" {
  unset TOFU_STATE_BUCKET

  run run_provider_setup

  assert_failure
  assert_output_contains "TOFU_STATE_BUCKET is missing"
}
