#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/rollback_alias"

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

# Helper: create a mock np script
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

# Helper: create a mock aws that fails
create_aws_error_mock() {
  local error_message="$1"
  echo "$error_message" > "$MOCK_BIN_DIR/aws_error.txt"
  cat > "$MOCK_BIN_DIR/aws" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/aws_error.txt" >&2
exit 1
OUTERSCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

@test "deployment/scripts/rollback_alias: fails when LAMBDA_FUNCTION_NAME is not set" {
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

@test "deployment/scripts/rollback_alias: fails when no previous version found without SCOPE_NRN" {
  export LAMBDA_FUNCTION_NAME="my-function"
  unset SCOPE_NRN

  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "❌ No previous version found to rollback to"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "This is the first deployment (no previous version exists)"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Manually set the alias version if the previous version is known"
}

@test "deployment/scripts/rollback_alias: fails when NRN returns empty previous version" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": ""}'

  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "❌ No previous version found to rollback to"
  assert_output_contains "NRN metadata was not stored properly for scope="
}

@test "deployment/scripts/rollback_alias: fails when NRN returns null previous version" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": null}'

  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "❌ No previous version found to rollback to"
}

@test "deployment/scripts/rollback_alias: uses default alias name 'main' when LAMBDA_MAIN_ALIAS_NAME not set" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  unset LAMBDA_MAIN_ALIAS_NAME

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "4"}'
  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "4"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "alias=main"
}

@test "deployment/scripts/rollback_alias: uses custom alias name when set" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_MAIN_ALIAS_NAME="live"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "4"}'
  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:live", "Name": "live", "FunctionVersion": "4"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "alias=live"
}

@test "deployment/scripts/rollback_alias: rolls back alias to previous version successfully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "4"}'
  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "4"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "🔄 Rolling back Lambda alias to previous version..."
  assert_output_contains "function_name=my-function"
  assert_output_contains "alias=main"
  assert_output_contains "previous_version=4"
  assert_output_contains "Updating alias main to point to version 4 on function my-function..."
  assert_output_contains "Alias main rolled back successfully to version 4"
  assert_output_contains "✨ Rollback complete - traffic restored to version 4 on function=my-function"
}

@test "deployment/scripts/rollback_alias: logs update-alias operation with correct details" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "4"}'
  create_aws_mock '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "Name": "main", "FunctionVersion": "4"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Updating alias main to point to version 4 on function my-function..."
  assert_output_contains "Alias main rolled back successfully to version 4"
}

@test "deployment/scripts/rollback_alias: fails when aws update-alias fails" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "4"}'
  create_aws_error_mock "ResourceNotFoundException: Alias main not found"

  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "❌ Failed to rollback alias main to version 4 on function my-function"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Version 4 no longer exists"
  assert_output_contains "Alias main does not exist on function my-function"
  assert_output_contains "Insufficient Lambda permissions"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Check if the version exists: aws lambda get-function --function-name my-function --qualifier 4"
  assert_output_contains "Verify alias exists: aws lambda get-alias --function-name my-function --name main"
}

@test "deployment/scripts/rollback_alias: retrieves previous version from NRN and uses it" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  create_np_mock '{"LAMBDA_FUNCTION_CURRENT_VERSION": "9"}'
  create_aws_mock '{"Name": "main", "FunctionVersion": "9"}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "previous_version=9"
  assert_output_contains "Updating alias main to point to version 9 on function my-function..."
  assert_output_contains "Rollback complete - traffic restored to version 9 on function=my-function"
}
