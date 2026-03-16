#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/store_nrn_metadata"

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

# Helper: create a mock np that fails
create_np_error_mock() {
  local error_message="${1:-An error occurred}"
  echo "$error_message" > "$MOCK_BIN_DIR/np_error.txt"
  cat > "$MOCK_BIN_DIR/np" <<'OUTERSCRIPT'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/np_error.txt" >&2
exit 1
OUTERSCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

@test "deployment/scripts/store_nrn_metadata: fails when SCOPE_NRN is not set" {
  unset SCOPE_NRN

  run bash "$SCRIPT"

  assert_failure
  assert_line "❌ SCOPE_NRN is required"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "Scope context not available in the environment"
  assert_output_contains "NRN not passed from the deployment pipeline"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Verify SCOPE_NRN is exported before this script runs"
  assert_output_contains "Check the deployment agent configuration"
}

@test "deployment/scripts/store_nrn_metadata: skips gracefully when ALB_RULE_PRIORITY is not set" {
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  unset ALB_RULE_PRIORITY

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "ALB_RULE_PRIORITY not set"
}

@test "deployment/scripts/store_nrn_metadata: stores alb_rule_priority when set" {
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export ALB_RULE_PRIORITY="150"

  create_np_mock '{"ok": true}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "📝 Storing ALB rule priority in NRN..."
  assert_output_contains "alb_rule_priority=150"
  assert_output_contains "Writing metadata to NRN=organization=1:account=2:namespace=3:application=4:scope=5..."
  assert_output_contains "Metadata stored successfully"
  assert_output_contains "✨ ALB rule priority stored for scope=organization=1:account=2:namespace=3:application=4:scope=5"
}

@test "deployment/scripts/store_nrn_metadata: logs NRN write target in output" {
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export ALB_RULE_PRIORITY="100"

  create_np_mock '{"ok": true}'

  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Writing metadata to NRN=organization=1:account=2:namespace=3:application=4:scope=5..."
}

@test "deployment/scripts/store_nrn_metadata: fails when np nrn write fails" {
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export ALB_RULE_PRIORITY="100"

  create_np_error_mock "Connection refused"

  run bash "$SCRIPT"

  assert_failure
  assert_output_contains "❌ Failed to write NRN metadata to scope=organization=1:account=2:namespace=3:application=4:scope=5"
  assert_output_contains "💡 Possible causes:"
  assert_output_contains "NRN service is unreachable"
  assert_output_contains "Invalid metadata JSON payload"
  assert_output_contains "Insufficient permissions to write to NRN"
  assert_output_contains "🔧 How to fix:"
  assert_output_contains "Check NRN service connectivity"
  assert_output_contains "Verify the metadata JSON is valid"
  assert_output_contains "Ensure the agent has write permissions to the NRN namespace"
}
