#!/bin/bash
# BATS test helper for Lambda scope scripts

# Source shared assertions from the testing framework
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAMBDA_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$LAMBDA_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/testing/assertions.sh" ]; then
  source "$PROJECT_ROOT/testing/assertions.sh"
fi

# Mock AWS CLI
_AWS_MOCK_RESPONSES=()
_AWS_MOCK_INDEX=0
_AWS_CALLS=()

mock_aws() {
  local response="$1"
  _AWS_MOCK_RESPONSES+=("$response")
}

mock_aws_error() {
  local error_message="${1:-An error occurred}"
  _AWS_MOCK_RESPONSES+=("ERROR:$error_message")
}

aws() {
  local call_args="$*"
  _AWS_CALLS+=("$call_args")

  if [ ${#_AWS_MOCK_RESPONSES[@]} -gt $_AWS_MOCK_INDEX ]; then
    local response="${_AWS_MOCK_RESPONSES[$_AWS_MOCK_INDEX]}"
    _AWS_MOCK_INDEX=$((_AWS_MOCK_INDEX + 1))

    if [[ "$response" == ERROR:* ]]; then
      echo "${response#ERROR:}" >&2
      return 1
    fi

    echo "$response"
    return 0
  fi

  echo "No mock response configured" >&2
  return 1
}

assert_aws_called() {
  local expected_pattern="$1"
  local found=false

  for call in "${_AWS_CALLS[@]}"; do
    if [[ "$call" == *"$expected_pattern"* ]]; then
      found=true
      break
    fi
  done

  if [ "$found" = false ]; then
    echo "Expected AWS call containing: $expected_pattern"
    echo "Actual calls:"
    for call in "${_AWS_CALLS[@]}"; do
      echo "  - $call"
    done
    return 1
  fi
}

assert_aws_called_with() {
  assert_aws_called "$@"
}

assert_aws_not_called() {
  if [ ${#_AWS_CALLS[@]} -gt 0 ]; then
    echo "Expected no AWS calls, but got:"
    for call in "${_AWS_CALLS[@]}"; do
      echo "  - $call"
    done
    return 1
  fi
}

get_aws_call() {
  local index="${1:-0}"
  if [ ${#_AWS_CALLS[@]} -gt $index ]; then
    echo "${_AWS_CALLS[$index]}"
  fi
}

get_aws_call_count() {
  echo "${#_AWS_CALLS[@]}"
}

reset_aws_mocks() {
  _AWS_MOCK_RESPONSES=()
  _AWS_MOCK_INDEX=0
  _AWS_CALLS=()
}

# Mock np CLI
_NP_MOCK_RESPONSES=()
_NP_MOCK_INDEX=0
_NP_CALLS=()

mock_np() {
  local response="$1"
  _NP_MOCK_RESPONSES+=("$response")
}

mock_np_error() {
  local error_message="${1:-An error occurred}"
  _NP_MOCK_RESPONSES+=("ERROR:$error_message")
}

np() {
  local call_args="$*"
  _NP_CALLS+=("$call_args")

  if [ ${#_NP_MOCK_RESPONSES[@]} -gt $_NP_MOCK_INDEX ]; then
    local response="${_NP_MOCK_RESPONSES[$_NP_MOCK_INDEX]}"
    _NP_MOCK_INDEX=$((_NP_MOCK_INDEX + 1))

    if [[ "$response" == ERROR:* ]]; then
      echo "${response#ERROR:}" >&2
      return 1
    fi

    echo "$response"
    return 0
  fi

  echo "No mock response configured" >&2
  return 1
}

assert_np_called() {
  local expected_pattern="$1"
  local found=false

  for call in "${_NP_CALLS[@]}"; do
    if [[ "$call" == *"$expected_pattern"* ]]; then
      found=true
      break
    fi
  done

  if [ "$found" = false ]; then
    echo "Expected np call containing: $expected_pattern"
    echo "Actual calls:"
    for call in "${_NP_CALLS[@]}"; do
      echo "  - $call"
    done
    return 1
  fi
}

get_np_call() {
  local index="${1:-0}"
  if [ ${#_NP_CALLS[@]} -gt $index ]; then
    echo "${_NP_CALLS[$index]}"
  fi
}

get_np_call_count() {
  echo "${#_NP_CALLS[@]}"
}

reset_np_mocks() {
  _NP_MOCK_RESPONSES=()
  _NP_MOCK_INDEX=0
  _NP_CALLS=()
}

# Lambda-specific JSON helpers (path-based extraction)
assert_json_path_equal() {
  local json="$1"
  local path="$2"
  local expected="$3"

  local actual
  actual=$(echo "$json" | jq -r "$path")

  if [ "$actual" != "$expected" ]; then
    echo "JSON assertion failed"
    echo "Path: $path"
    echo "Expected: $expected"
    echo "Actual: $actual"
    return 1
  fi
}

assert_json_has_key() {
  local json="$1"
  local key="$2"

  if ! echo "$json" | jq -e "has(\"$key\")" > /dev/null 2>&1; then
    echo "JSON does not have key: $key"
    return 1
  fi
}

assert_json_array_length() {
  local json="$1"
  local path="$2"
  local expected_length="$3"

  local actual_length
  actual_length=$(echo "$json" | jq -r "$path | length")

  if [ "$actual_length" != "$expected_length" ]; then
    echo "JSON array length assertion failed"
    echo "Path: $path"
    echo "Expected length: $expected_length"
    echo "Actual length: $actual_length"
    return 1
  fi
}

# Environment Setup Helpers
setup_test_env() {
  reset_aws_mocks
  reset_np_mocks

  unset CONTEXT
  unset TOFU_VARIABLES
  unset MODULES_TO_USE
  unset LAMBDA_FUNCTION_NAME
  unset LAMBDA_MAIN_ALIAS_NAME
  unset LAMBDA_WARMUP_ALIAS_NAME
  unset SCOPE_DOMAIN
  unset NEW_VERSION
  unset OLD_VERSION
  unset TRAFFIC_PERCENTAGE
  unset VERSION
  unset SCOPE_ID
  unset SCOPE_SLUG
  unset SCOPE_NRN
  unset NAMESPACE_SLUG
  unset APPLICATION_SLUG
  unset ACCOUNT_SLUG
  unset VISIBILITY
}

teardown_test_env() {
  reset_aws_mocks
  reset_np_mocks
}

# Script Running Helper
run_script() {
  local script_path="$1"
  shift

  export -f aws
  export -f np

  bash "$script_path" "$@"
}

# BATS-compatible assertions
assert_success() {
  if [ "$status" -ne 0 ]; then
    echo "Expected success (exit 0), got exit $status"
    echo "Output: $output"
    return 1
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    echo "Expected failure (non-zero exit), got exit 0"
    echo "Output: $output"
    return 1
  fi
}

assert_line() {
  local expected="$1"
  local found=false

  while IFS= read -r line; do
    if [[ "$line" == "$expected" ]]; then
      found=true
      break
    fi
  done <<< "$output"

  if [ "$found" = false ]; then
    echo "Expected output to contain line: $expected"
    echo "Actual output:"
    echo "$output"
    return 1
  fi
}

assert_output_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

assert_output_not_contains() {
  local unexpected="$1"
  if [[ "$output" == *"$unexpected"* ]]; then
    echo "Expected output NOT to contain: $unexpected"
    echo "Actual output: $output"
    return 1
  fi
}

# Run a script the way the workflow engine does. These scripts use `return` as
# their exit path, which `bash <script>` turns into a warning instead of an exit.
run_sourced() {
  run bash -c "source '${1:-$SCRIPT}'"
}

# Export all functions for use in tests
export -f mock_aws mock_aws_error aws assert_aws_called assert_aws_called_with assert_aws_not_called get_aws_call get_aws_call_count reset_aws_mocks
export -f mock_np mock_np_error np assert_np_called get_np_call get_np_call_count reset_np_mocks
export -f assert_json_path_equal assert_json_has_key assert_json_array_length
export -f setup_test_env teardown_test_env
export -f run_script run_sourced
export -f assert_success assert_failure assert_line assert_output_contains assert_output_not_contains
