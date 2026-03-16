#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  # Create temp dir for mock binaries
  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  _TEST_CLEANUP_DIRS=("$MOCK_BIN_DIR")

  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export SCOPE_ID="scope-123"
  export DEPLOYMENT_ID="deploy-abc"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export RESOURCE_TAGS_JSON='{"Environment":"test","Team":"platform"}'

  # Unset exported shell functions so file-based mocks on PATH take precedence
  unset -f aws np
}

teardown() {
  teardown_test_env
  for dir in "${_TEST_CLEANUP_DIRS[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir"
  done
}

# Helper: create a mock np script
create_np_mock() {
  local responses_file="$MOCK_BIN_DIR/np_responses"
  local index_file="$MOCK_BIN_DIR/np_index"
  echo "0" > "$index_file"
  > "$responses_file"

  for resp in "$@"; do
    echo "$resp" >> "$responses_file"
  done

  cat > "$MOCK_BIN_DIR/np" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
INDEX=$(cat "$MOCK_DIR/np_index")
RESPONSE=$(sed -n "$((INDEX + 1))p" "$MOCK_DIR/np_responses")
echo $((INDEX + 1)) > "$MOCK_DIR/np_index"
EXIT_CODE="${RESPONSE%%:*}"
OUTPUT="${RESPONSE#*:}"
if [ "$EXIT_CODE" != "0" ]; then
  echo "$OUTPUT" >&2
  exit "$EXIT_CODE"
fi
echo "$OUTPUT"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

# Helper: create a mock aws script
create_aws_mock() {
  local responses_file="$MOCK_BIN_DIR/aws_responses"
  local index_file="$MOCK_BIN_DIR/aws_index"
  echo "0" > "$index_file"
  > "$responses_file"

  for resp in "$@"; do
    echo "$resp" >> "$responses_file"
  done

  cat > "$MOCK_BIN_DIR/aws" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
INDEX=$(cat "$MOCK_DIR/aws_index")
RESPONSE=$(sed -n "$((INDEX + 1))p" "$MOCK_DIR/aws_responses")
echo $((INDEX + 1)) > "$MOCK_DIR/aws_index"
EXIT_CODE="${RESPONSE%%:*}"
OUTPUT="${RESPONSE#*:}"
if [ "$EXIT_CODE" != "0" ]; then
  echo "$OUTPUT" >&2
  exit "$EXIT_CODE"
fi
echo "$OUTPUT"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

@test "sync_parameters: skips when strategy is env" {
  export PARAMETERS_STRATEGY="env"
  set_context secretsmanager

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_success
  assert_output_contains "skipping Secrets Manager sync"
}

@test "sync_parameters: skips when strategy not set" {
  unset PARAMETERS_STRATEGY
  set_context secretsmanager

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_success
  assert_output_contains "skipping Secrets Manager sync"
}

@test "sync_parameters: creates new secret when not exists" {
  export PARAMETERS_STRATEGY="secretsmanager"
  set_context secretsmanager

  create_aws_mock \
    '1:ResourceNotFoundException: Secret not found' \
    '0:{"ARN":"arn:aws:secretsmanager:us-east-1:123456789012:secret:nullplatform/scope-123/deploy-abc/parameters"}'

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_success
  assert_output_contains "Secret not found - creating new secret"
  assert_output_contains "Secret created"
}

@test "sync_parameters: updates existing secret" {
  export PARAMETERS_STRATEGY="secretsmanager"
  set_context secretsmanager

  create_aws_mock \
    '0:{"ARN":"arn:aws:secretsmanager:us-east-1:123456789012:secret:nullplatform/scope-123/deploy-abc/parameters"}'

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_success
  assert_output_contains "Secret updated"
}

@test "sync_parameters: fails when SCOPE_ID not set" {
  export PARAMETERS_STRATEGY="secretsmanager"
  unset SCOPE_ID
  set_context secretsmanager

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_failure
  assert_output_contains "SCOPE_ID is not set"
}

@test "sync_parameters: handles empty parameters" {
  export PARAMETERS_STRATEGY="secretsmanager"
  export CONTEXT='{"parameters":{"results":[]}}'

  create_aws_mock \
    '0:{"ARN":"arn:aws:secretsmanager:us-east-1:123456789012:secret:nullplatform/scope-123/deploy-abc/parameters"}'

  run bash "$LAMBDA_DIR/deployment/scripts/sync_parameters_to_secrets_manager"

  assert_success
  assert_output_contains "No parameters to sync"
}
