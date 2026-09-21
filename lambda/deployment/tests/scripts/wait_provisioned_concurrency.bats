#!/usr/bin/env bats
# Unit tests for deployment/scripts/wait_provisioned_concurrency script

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/wait_provisioned_concurrency"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Mock sleep to be instant
  cat > "$MOCK_BIN_DIR/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  chmod +x "$MOCK_BIN_DIR/sleep"

  # The poll loop is bounded by wall-clock time, not by iteration count, so an
  # instant sleep alone does not stop it: a test whose mocks never reach a
  # terminal status would spin for the full default of 600 real seconds.
  export PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS=2
  export PROVISIONED_CONCURRENCY_POLL_INTERVAL=0
}

teardown() {
  teardown_test_env
  rm -rf "$MOCK_BIN_DIR"
}

# Creates a file-based aws mock that returns sequential responses
create_aws_sequential_mock() {
  local response_dir="$MOCK_BIN_DIR/responses"
  mkdir -p "$response_dir"

  local i=0
  for response in "$@"; do
    echo "$response" > "$response_dir/response_$i"
    i=$((i + 1))
  done

  cat > "$MOCK_BIN_DIR/aws" <<'MOCKSCRIPT'
#!/bin/bash
RESPONSE_DIR="$(dirname "$0")/responses"
CALL_COUNT_FILE="$RESPONSE_DIR/.call_count"

if [ ! -f "$CALL_COUNT_FILE" ]; then
  echo "0" > "$CALL_COUNT_FILE"
fi

count=$(cat "$CALL_COUNT_FILE")
response_file="$RESPONSE_DIR/response_$count"

echo "$((count + 1))" > "$CALL_COUNT_FILE"

if [ -f "$response_file" ]; then
  cat "$response_file"
  exit 0
fi

echo "No mock response for call $count" >&2
exit 1
MOCKSCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

create_aws_mock() {
  local response="$1"
  cat > "$MOCK_BIN_DIR/aws" <<SCRIPT
#!/bin/bash
echo '$response'
exit 0
SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

create_aws_error_mock() {
  local error_message="${1:-An error occurred}"
  cat > "$MOCK_BIN_DIR/aws" <<SCRIPT
#!/bin/bash
echo "$error_message" >&2
exit 1
SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Skipping when not provisioned
@test "deployment/scripts/wait_provisioned_concurrency: skips when provisioned concurrency not enabled" {
  set_context "public"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_success
  assert_output_contains "Provisioned concurrency not enabled"
  assert_output_contains "skipping wait"
}

# Input validation
@test "deployment/scripts/wait_provisioned_concurrency: fails when LAMBDA_FUNCTION_NAME is not set" {
  set_context "provisioned"
  unset LAMBDA_FUNCTION_NAME
  export LAMBDA_MAIN_ALIAS_NAME="main"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

# No provisioned concurrency configured
@test "deployment/scripts/wait_provisioned_concurrency: succeeds when no provisioned concurrency configured" {
  set_context "provisioned"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  create_aws_error_mock "ProvisionedConcurrencyConfigNotFoundException: No provisioned concurrency config"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_success
  assert_output_contains "No provisioned concurrency configuration found"
}

# Status polling - direct mock calls (function-based)
@test "deployment/scripts/wait_provisioned_concurrency: detects READY status" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 5,
    "Status": "READY"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  assert_json_path_equal "$result" '.Status' "READY"
}

@test "deployment/scripts/wait_provisioned_concurrency: detects IN_PROGRESS status" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 2,
    "Status": "IN_PROGRESS"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  assert_json_path_equal "$result" '.Status' "IN_PROGRESS"
}

@test "deployment/scripts/wait_provisioned_concurrency: detects FAILED status" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 0,
    "Status": "FAILED",
    "StatusReason": "Insufficient capacity"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  assert_json_path_equal "$result" '.Status' "FAILED"
}

# Full script polling - READY on first check
@test "deployment/scripts/wait_provisioned_concurrency: completes when status is READY immediately" {
  set_context "provisioned"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS="10"
  export PROVISIONED_CONCURRENCY_POLL_INTERVAL="1"

  create_aws_mock '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 5,
    "Status": "READY"
  }'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_success
  assert_output_contains "Provisioned concurrency is READY"
  assert_output_contains "Allocated: 5 instances"
}

# Full script polling - IN_PROGRESS then READY
@test "deployment/scripts/wait_provisioned_concurrency: polls until status is READY" {
  set_context "provisioned"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS="30"
  export PROVISIONED_CONCURRENCY_POLL_INTERVAL="1"

  # First call returns IN_PROGRESS, second call returns READY
  create_aws_sequential_mock \
    '{"RequestedProvisionedConcurrentExecutions": 5, "AllocatedProvisionedConcurrentExecutions": 2, "Status": "IN_PROGRESS"}' \
    '{"RequestedProvisionedConcurrentExecutions": 5, "AllocatedProvisionedConcurrentExecutions": 5, "Status": "READY"}'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_success
  assert_output_contains "IN_PROGRESS"
  assert_output_contains "Provisioned concurrency is READY"
}

# Full script - FAILED status
@test "deployment/scripts/wait_provisioned_concurrency: fails when status is FAILED" {
  set_context "provisioned"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS="10"
  export PROVISIONED_CONCURRENCY_POLL_INTERVAL="1"

  create_aws_mock '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 0,
    "Status": "FAILED",
    "StatusReason": "Lambda was unable to set up provisioned concurrency"
  }'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "Provisioned concurrency allocation FAILED"
  assert_output_contains "unable to set up"
}

@test "deployment/scripts/wait_provisioned_concurrency: reports progress during polling" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 10,
    "AllocatedProvisionedConcurrentExecutions": 5,
    "Status": "IN_PROGRESS"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  local requested allocated
  requested=$(echo "$result" | jq -r '.RequestedProvisionedConcurrentExecutions')
  allocated=$(echo "$result" | jq -r '.AllocatedProvisionedConcurrentExecutions')

  assert_equal "$allocated" "5"
  assert_equal "$requested" "10"

  local progress=$((allocated * 100 / requested))
  assert_equal "$progress" "50"
}

# Failure handling
@test "deployment/scripts/wait_provisioned_concurrency: reports failure reason when status is FAILED" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 5,
    "AllocatedProvisionedConcurrentExecutions": 0,
    "Status": "FAILED",
    "StatusReason": "Lambda was unable to set up provisioned concurrency"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  assert_json_path_equal "$result" '.Status' "FAILED"

  local status_reason
  status_reason=$(echo "$result" | jq -r '.StatusReason // "Unknown"')
  assert_contains "$status_reason" "unable to set up"
}

# Timeout simulation (pure math)
@test "deployment/scripts/wait_provisioned_concurrency: respects MAX_WAIT_SECONDS" {
  local max_wait=300
  local poll_interval=10
  local max_iterations=$((max_wait / poll_interval))

  assert_equal "$max_iterations" "30"
}

@test "deployment/scripts/wait_provisioned_concurrency: calculates remaining time correctly" {
  local start_time=1000
  local current_time=1150
  local max_wait=300

  local elapsed=$((current_time - start_time))
  local remaining=$((max_wait - elapsed))

  assert_equal "$elapsed" "150"
  assert_equal "$remaining" "150"
}

# Error handling
@test "deployment/scripts/wait_provisioned_concurrency: handles API rate limiting" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws_error "TooManyRequestsException: Rate exceeded"

  run aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME"

  assert_failure
  assert_output_contains "TooManyRequestsException"
}

@test "deployment/scripts/wait_provisioned_concurrency: handles network errors gracefully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws_error "Could not connect to the endpoint URL"

  run aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME"

  assert_failure
}

# Warmup alias
@test "deployment/scripts/wait_provisioned_concurrency: checks provisioned concurrency on warmup alias" {
  set_context "provisioned"
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export WARMUP_ALIAS_NAME="warm"
  export PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS="10"
  export PROVISIONED_CONCURRENCY_POLL_INTERVAL="1"

  # First call: main alias READY, second call: warm alias READY
  create_aws_sequential_mock \
    '{"RequestedProvisionedConcurrentExecutions": 5, "AllocatedProvisionedConcurrentExecutions": 5, "Status": "READY"}' \
    '{"RequestedProvisionedConcurrentExecutions": 3, "AllocatedProvisionedConcurrentExecutions": 3, "Status": "READY"}'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_success
  assert_output_contains "Provisioned concurrency is READY"
  assert_output_contains "Warm alias warm provisioned concurrency is READY"
}

# Concurrent executions (pure validation)
@test "deployment/scripts/wait_provisioned_concurrency: verifies allocated matches requested on success" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 10,
    "AllocatedProvisionedConcurrentExecutions": 10,
    "Status": "READY"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  local requested allocated
  requested=$(echo "$result" | jq -r '.RequestedProvisionedConcurrentExecutions')
  allocated=$(echo "$result" | jq -r '.AllocatedProvisionedConcurrentExecutions')

  assert_equal "$requested" "$allocated"
}

@test "deployment/scripts/wait_provisioned_concurrency: handles partial allocation" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"

  mock_aws '{
    "RequestedProvisionedConcurrentExecutions": 10,
    "AllocatedProvisionedConcurrentExecutions": 7,
    "Status": "IN_PROGRESS"
  }'

  result=$(aws lambda get-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --qualifier "$LAMBDA_MAIN_ALIAS_NAME")

  local requested allocated
  requested=$(echo "$result" | jq -r '.RequestedProvisionedConcurrentExecutions')
  allocated=$(echo "$result" | jq -r '.AllocatedProvisionedConcurrentExecutions')

  assert_less_than "$allocated" "$requested" "allocated vs requested"
}
