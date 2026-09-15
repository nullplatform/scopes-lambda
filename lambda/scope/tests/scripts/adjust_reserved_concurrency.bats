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
  export LAMBDA_FUNCTION_NAME="my-test-function"

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

run_sourced() {
  source "$LAMBDA_DIR/scope/scripts/adjust_reserved_concurrency"
}

@test "adjust_reserved: sets concurrency value" {
  export CONTEXT='{"parameters":{"value":"10"}}'

  create_np_mock \
    '0:{"LAMBDA_CURRENT_RESERVED_CONCURRENCY_VALUE":"5"}' \
    '0:' \
    '0:'

  create_aws_mock \
    '0:{"ReservedConcurrentExecutions": 10}'

  run run_sourced

  assert_success
  assert_output_contains "Reserved concurrency set to 10"
}

@test "adjust_reserved: removes reservation when value is 0" {
  export CONTEXT='{"parameters":{"value":"0"}}'

  create_np_mock \
    '0:{"LAMBDA_CURRENT_RESERVED_CONCURRENCY_VALUE":"5"}' \
    '0:' \
    '0:'

  create_aws_mock \
    '0:'

  run run_sourced

  assert_success
  assert_output_contains "reservation removed"
}

@test "adjust_reserved: fails when value not provided" {
  export CONTEXT='{"parameters":{}}'

  run run_sourced

  assert_failure
}

@test "adjust_reserved: fails when value is not a number" {
  export CONTEXT='{"parameters":{"value":"abc"}}'

  run run_sourced

  assert_failure
  assert_output_contains "must be a non-negative integer"
}

@test "adjust_reserved: fails when LAMBDA_FUNCTION_NAME not set" {
  unset LAMBDA_FUNCTION_NAME
  export CONTEXT='{"parameters":{"value":"10"}}'

  run run_sourced

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}
