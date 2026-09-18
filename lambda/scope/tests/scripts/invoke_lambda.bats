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
  MOCK_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN_DIR"
  export PATH="$MOCK_BIN_DIR:$PATH"
  _TEST_CLEANUP_DIRS=("$MOCK_BIN_DIR")

  export SCOPE_NRN="organization=1:account=2:namespace=3:application=4:scope=5"
  export LAMBDA_FUNCTION_NAME="my-test-function"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR"
  export NP_ACTION_CONTEXT='{"notification":{"parameters":{}}}'

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

# Helper: create a mock aws script that also writes a response file for invoke
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

# If this is a lambda invoke call, write a response file to the last argument
if [[ "$*" == *"lambda invoke"* ]]; then
  RESPONSE_FILE="${@: -1}"
  RESPONSE_DIR="$(dirname "$RESPONSE_FILE")"
  if [ -d "$RESPONSE_DIR" ]; then
    echo '{"statusCode": 200, "body": "OK"}' > "$RESPONSE_FILE"
  fi
fi

if [ "$EXIT_CODE" != "0" ]; then
  echo "$OUTPUT" >&2
  exit "$EXIT_CODE"
fi
echo "$OUTPUT"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Helper: create aws mock that writes a custom response file for invoke
create_aws_mock_with_response() {
  local response_body="$1"
  shift

  local responses_file="$MOCK_BIN_DIR/aws_responses"
  local index_file="$MOCK_BIN_DIR/aws_index"
  local custom_body_file="$MOCK_BIN_DIR/aws_invoke_body"
  echo "0" > "$index_file"
  > "$responses_file"
  echo "$response_body" > "$custom_body_file"

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

# If this is a lambda invoke call, write the custom response file
if [[ "$*" == *"lambda invoke"* ]]; then
  RESPONSE_FILE="${@: -1}"
  RESPONSE_DIR="$(dirname "$RESPONSE_FILE")"
  if [ -d "$RESPONSE_DIR" ]; then
    cat "$MOCK_DIR/aws_invoke_body" > "$RESPONSE_FILE"
  fi
fi

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
  source "$LAMBDA_DIR/scope/scripts/invoke_lambda"
}

@test "invoke: succeeds with default payload" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_MAIN_ALIAS":"main"}'

  create_aws_mock \
    '0:{"StatusCode": 200}'

  run run_sourced

  assert_success
  assert_line "   📋 function_name=my-test-function | alias=main | payload_size=2"
  assert_output_contains "Lambda invoked successfully"
}

@test "invoke: fails when LAMBDA_FUNCTION_NAME not set" {
  unset LAMBDA_FUNCTION_NAME

  run run_sourced

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "invoke: handles function error" {
  create_np_mock \
    '0:{"LAMBDA_FUNCTION_MAIN_ALIAS":"main"}'

  create_aws_mock_with_response \
    '{"errorMessage":"Runtime.HandlerNotFound","errorType":"Runtime.HandlerNotFound"}' \
    '0:{"StatusCode": 200, "FunctionError": "Unhandled"}'

  run run_sourced

  assert_failure
  assert_output_contains "Lambda function returned an error"
}

@test "invoke: uses the payload from the action notification" {
  export NP_ACTION_CONTEXT='{"notification":{"parameters":{"payload":"{\"key\":\"value\"}"}}}'

  create_np_mock \
    '0:{"LAMBDA_FUNCTION_MAIN_ALIAS":"main"}'

  create_aws_mock \
    '0:{"StatusCode": 200}'

  run run_sourced

  assert_success
  assert_line "   📋 function_name=my-test-function | alias=main | payload_size=15"
  assert_line "   📡 Invoking my-test-function:main..."
}
