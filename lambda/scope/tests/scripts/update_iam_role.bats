#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/update_iam_role"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  export CONTEXT='{}'
  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

np_returns() {
  cat > "$MOCK_BIN_DIR/np" <<MOCK
#!/bin/bash
echo "Warning: unknown flag, ignoring" >&2
cat <<'PAYLOAD'
$1
PAYLOAD
MOCK
  chmod +x "$MOCK_BIN_DIR/np"
}

# The engine sources every step into one shell: an exit here skips the rest.
run_step_then_next() {
  run bash -c "source '$SCRIPT'; echo NEXT_STEP_RAN"
}

@test "update_iam_role: an early return lets the next step run" {
  np_returns '{"namespaces":{"global":{}},"omittedKeys":["aws.AWS_DEDICATED_ROLE_NAME"]}'

  run_step_then_next

  assert_success
  assert_line "🔍 Updating IAM role configuration..."
  assert_line "   ✅ No scope-managed role to update"
  assert_line "NEXT_STEP_RAN"
}

@test "update_iam_role: reads the dedicated role name from the aws namespace" {
  np_returns '{"namespaces":{"aws":{"AWS_DEDICATED_ROLE_NAME":"my-dedicated-role"}}}'

  run_step_then_next

  assert_success
  assert_line "🔍 Updating IAM role configuration..."
  assert_line "   📡 Checking current VPC policy state for role 'my-dedicated-role'..."
  assert_line "   ✅ No VPC policy changes needed (vpc_enabled=false, policy_attached=false)"
  assert_line "✨ IAM role update complete for role 'my-dedicated-role'"
  assert_line "NEXT_STEP_RAN"
}

@test "update_iam_role: a warning on stderr does not corrupt the role lookup" {
  np_returns '{"namespaces":{"aws":{"AWS_DEDICATED_ROLE_NAME":"my-dedicated-role"}}}'

  run_step_then_next

  assert_success
  assert_output_not_contains "parse error"
  assert_output_not_contains "No scope-managed role to update"
}

@test "update_iam_role: skips a role the scope does not manage" {
  export CONTEXT='{"providers":{"scope-configurations":{"lambda":{"use_dedicated_role":"true"}}}}'
  np_returns '{"namespaces":{"aws":{"AWS_DEDICATED_ROLE_NAME":"customer-role"}}}'

  run_step_then_next

  assert_success
  assert_line "🔍 Updating IAM role configuration..."
  assert_line "   ✅ No scope-managed role to update"
  assert_line "NEXT_STEP_RAN"
}
