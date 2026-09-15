#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/cleanup_old_version"

  # Create temp dir for file-based mocks
  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Unset exported functions so PATH-based mocks take precedence
  unset -f aws np
}

teardown() {
  teardown_test_env
  rm -rf "$MOCK_BIN_DIR"
}

# Helper: create a mock np script that outputs given JSON
create_np_mock() {
  local response="$1"
  local exit_code="${2:-0}"
  echo "$response" > "$MOCK_BIN_DIR/np_response.txt"
  cat > "$MOCK_BIN_DIR/np" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/np_response.txt"
OUTERSCRIPT
  echo "exit $exit_code" >> "$MOCK_BIN_DIR/np"
  chmod +x "$MOCK_BIN_DIR/np"
}

# Helper: create a mock aws script
create_aws_mock() {
  local response="$1"
  local exit_code="${2:-0}"
  echo "$response" > "$MOCK_BIN_DIR/aws_response.txt"
  cat > "$MOCK_BIN_DIR/aws" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/aws_response.txt"
OUTERSCRIPT
  echo "exit $exit_code" >> "$MOCK_BIN_DIR/aws"
  chmod +x "$MOCK_BIN_DIR/aws"
}

@test "deployment/scripts/cleanup_old_version: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME

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

@test "deployment/scripts/cleanup_old_version: skips when SCOPE_NRN is not set and no previous version" {
  export LAMBDA_FUNCTION_NAME="my-function"
  unset SCOPE_NRN

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No previous version found to cleanup"
}

@test "deployment/scripts/cleanup_old_version: skips when NRN returns no previous version" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": ""}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No previous version found to cleanup"
}

@test "deployment/scripts/cleanup_old_version: skips when previous version is null" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": null}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  No previous version found to cleanup"
}

@test "deployment/scripts/cleanup_old_version: skips deletion of \$LATEST (protected)" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": "$LATEST"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Skipping deletion of version"
  assert_output_contains "(protected)"
}

@test "deployment/scripts/cleanup_old_version: skips deletion of version 1 (protected)" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": "1"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "⏭️  Skipping deletion of version 1 (protected)"
}

@test "deployment/scripts/cleanup_old_version: deletes previous version successfully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": "3"}'
  create_aws_mock ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "🧹 Cleaning up old Lambda version..."
  assert_output_contains "function_name=my-function"
  assert_output_contains "old_version=3"
  assert_output_contains "Deleting Lambda version 3 from function my-function..."
  assert_output_contains "Old version 3 cleanup complete"
  assert_output_contains "✨ Cleanup finished for function=my-function version=3"
}

@test "deployment/scripts/cleanup_old_version: succeeds even when aws delete-function fails" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": "3"}'
  create_aws_mock "ResourceNotFoundException: Version 3 not found" 1

  run bash "$SCRIPT"

  # Script uses || true, so it should still succeed
  assert_success
  assert_output_contains "Cleanup finished for function=my-function version=3"
}

@test "deployment/scripts/cleanup_old_version: reads previous version from NRN and uses it for deletion" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_PREVIOUS_VERSION": "12"}'
  create_aws_mock ""

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "old_version=12"
  assert_output_contains "Deleting Lambda version 12 from function my-function..."
}

@test "deployment/scripts/cleanup_old_version: handles np nrn read failure gracefully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock "" 1

  run bash "$SCRIPT"

  # np failure results in empty old_version, so it skips
  assert_success
  assert_output_contains "⏭️  No previous version found to cleanup"
}
