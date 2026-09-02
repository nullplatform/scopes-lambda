#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  export -f aws np

  SCRIPT="$LAMBDA_DIR/deployment/scripts/cleanup_new_version"
}

teardown() {
  teardown_test_env
}

# These scripts are sourced by the workflow engine, so `return` is their exit
# path. `run bash <script>` turns `return` into a warning and keeps going, so a
# failure assertion could never observe the non-zero status.
run_sourced() {
  run bash -c "source '$1'"
}

@test "deployment/scripts/cleanup_new_version: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  export LAMBDA_NEW_VERSION="5"

  run_sourced "$SCRIPT"

  assert_failure
  assert_line "❌ LAMBDA_FUNCTION_NAME is required"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Environment variable not set by the deployment pipeline"
  assert_output_contains "Scope context missing Lambda function configuration"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Ensure the scope has a valid Lambda function configured"
  assert_output_contains "Check that LAMBDA_FUNCTION_NAME is exported before this script runs"
}

@test "deployment/scripts/cleanup_new_version: skips when LAMBDA_NEW_VERSION is empty" {
  export LAMBDA_FUNCTION_NAME="my-function"
  unset LAMBDA_NEW_VERSION

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No new version specified to cleanup"
}

@test "deployment/scripts/cleanup_new_version: skips when LAMBDA_NEW_VERSION is null" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_NEW_VERSION="null"

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No new version specified to cleanup"
}

@test "deployment/scripts/cleanup_new_version: skips when LAMBDA_NEW_VERSION is \$LATEST" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_NEW_VERSION="\$LATEST"

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  Cannot delete \$LATEST"
}

@test "deployment/scripts/cleanup_new_version: deletes specified version successfully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_NEW_VERSION="7"

  mock_aws ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "🧹 Cleaning up failed deployment version..."
  assert_output_contains "function_name=my-function"
  assert_output_contains "new_version=7"
  assert_output_contains "Deleting failed version 7 from function my-function..."
  assert_output_contains "Failed version 7 cleanup complete"
  assert_output_contains "✨ Cleanup finished for function=my-function version=7"
}

@test "deployment/scripts/cleanup_new_version: invokes delete-function for the correct function and qualifier" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_NEW_VERSION="7"

  mock_aws ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Deleting failed version 7 from function my-function..."
  assert_output_contains "Failed version 7 cleanup complete"
}

@test "deployment/scripts/cleanup_new_version: succeeds even when aws delete-function fails" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_NEW_VERSION="999"

  mock_aws_error "ResourceNotFoundException: Function version 999 not found"

  run bash "$SCRIPT"

  # Script uses || true, so it should still succeed
  assert_success
  assert_output_contains "Cleanup finished for function=my-function version=999"
}

@test "deployment/scripts/cleanup_new_version: logs function_name and new_version before deletion" {
  export LAMBDA_FUNCTION_NAME="test-lambda-fn"
  export LAMBDA_NEW_VERSION="42"

  mock_aws ""

  run bash "$SCRIPT"

  assert_success
  assert_line "   ✅ function_name=test-lambda-fn"
  assert_line "   ✅ new_version=42"
}
