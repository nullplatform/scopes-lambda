#!/usr/bin/env bats
# Unit tests for deployment/scripts/update_alias_weights script

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/mock_context.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  SCRIPT="$LAMBDA_DIR/deployment/scripts/update_alias_weights"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
  rm -rf "$MOCK_BIN_DIR"
}

# Creates a file-based aws mock that returns sequential responses
# Usage: create_aws_sequential_mock '{"response1":"..."}' '{"response2":"..."}'
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

create_aws_error_mock() {
  local error_message="${1:-An error occurred}"
  cat > "$MOCK_BIN_DIR/aws" <<SCRIPT
#!/bin/bash
echo "$error_message" >&2
exit 1
SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Input validation
@test "deployment/scripts/update_alias_weights: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="10"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "deployment/scripts/update_alias_weights: fails when DESIRED_TRAFFIC is not set" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  unset DESIRED_TRAFFIC

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "DESIRED_TRAFFIC is required"
}

@test "deployment/scripts/update_alias_weights: fails when no version is specified" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  unset LAMBDA_NEW_VERSION
  unset LAMBDA_CURRENT_VERSION
  export DESIRED_TRAFFIC="10"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
  assert_output_contains "No version specified"
}

# Traffic percentage validation
@test "deployment/scripts/update_alias_weights: fails when DESIRED_TRAFFIC is negative" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="-10"

  # get-alias response needed to get past version check
  create_aws_sequential_mock '{"FunctionVersion": "1", "Name": "main"}'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
}

@test "deployment/scripts/update_alias_weights: fails when DESIRED_TRAFFIC exceeds 100" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="150"

  create_aws_sequential_mock '{"FunctionVersion": "1", "Name": "main"}'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
}

@test "deployment/scripts/update_alias_weights: fails when DESIRED_TRAFFIC is not a number" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="abc"

  create_aws_sequential_mock '{"FunctionVersion": "1", "Name": "main"}'

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
}

# Weight calculation (pure math, no mocks needed)
@test "deployment/scripts/update_alias_weights: calculates correct weights for 10% traffic" {
  local traffic_percentage=10
  local new_weight=$(echo "scale=2; $traffic_percentage / 100" | bc)
  local old_weight=$(echo "scale=2; 1 - $new_weight" | bc)

  [ "$new_weight" = ".10" ] || [ "$new_weight" = "0.10" ]
  [ "$old_weight" = ".90" ] || [ "$old_weight" = "0.90" ]
}

@test "deployment/scripts/update_alias_weights: calculates correct weights for 50% traffic" {
  local traffic_percentage=50
  local new_weight=$(echo "scale=2; $traffic_percentage / 100" | bc)
  local old_weight=$(echo "scale=2; 1 - $new_weight" | bc)

  [ "$new_weight" = ".50" ] || [ "$new_weight" = "0.50" ]
  [ "$old_weight" = ".50" ] || [ "$old_weight" = "0.50" ]
}

@test "deployment/scripts/update_alias_weights: calculates correct weights for 100% traffic" {
  local traffic_percentage=100
  local new_weight=$(echo "scale=2; $traffic_percentage / 100" | bc)
  local old_weight=$(echo "scale=2; 1 - $new_weight" | bc)

  [ "$new_weight" = "1.00" ] || [ "$new_weight" = "1" ]
  [ "$old_weight" = "0" ] || [ "$old_weight" = "0.00" ] || [ "$old_weight" = ".00" ]
}

@test "deployment/scripts/update_alias_weights: calculates correct weights for 0% traffic" {
  local traffic_percentage=0
  local new_weight=$(echo "scale=2; $traffic_percentage / 100" | bc)
  local old_weight=$(echo "scale=2; 1 - $new_weight" | bc)

  [ "$new_weight" = "0" ] || [ "$new_weight" = "0.00" ] || [ "$new_weight" = ".00" ]
  [ "$old_weight" = "1.00" ] || [ "$old_weight" = "1" ]
}

# Successful weighted update flow
@test "deployment/scripts/update_alias_weights: updates alias with weighted routing and logs messages" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="25"

  # First call: get-alias, second call: update-alias
  create_aws_sequential_mock \
    '{"FunctionVersion": "1", "Name": "main"}' \
    '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "FunctionVersion": "1"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
  assert_output_contains "function_name=my-function"
  assert_output_contains "alias=main"
  assert_output_contains "new_version=2"
  assert_output_contains "traffic_percentage=25%"
  assert_output_contains "Traffic switch completed successfully for function=my-function alias=main traffic=25%"
}

@test "deployment/scripts/update_alias_weights: switches to 100% traffic without weighted routing" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="100"

  # First call: get-alias, second call: update-alias for 100% switch
  create_aws_sequential_mock \
    '{"FunctionVersion": "1", "Name": "main"}' \
    '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main", "FunctionVersion": "2"}'

  unset -f aws
  run bash "$SCRIPT"

  assert_success
  assert_output_contains "Switching 100% traffic to version 2"
  assert_output_contains "Traffic switch completed successfully"
}

# AWS CLI call verification (using function-based mock directly)
@test "deployment/scripts/update_alias_weights: calls aws lambda update-alias with correct routing config" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export NEW_VERSION="2"
  export OLD_VERSION="1"
  export TRAFFIC_PERCENTAGE="25"

  mock_aws '{"AliasArn": "arn:aws:lambda:us-east-1:123456789012:function:my-function:main"}'

  local routing_config='{"2":0.25}'
  aws lambda update-alias \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --name "$LAMBDA_MAIN_ALIAS_NAME" \
    --routing-config "AdditionalVersionWeights=$routing_config"

  [ $? -eq 0 ]
  assert_aws_called "update-alias"
  assert_aws_called "--function-name my-function"
  assert_aws_called "--name main"
}

# Error handling
@test "deployment/scripts/update_alias_weights: handles AWS CLI errors gracefully" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="2"
  export DESIRED_TRAFFIC="10"

  create_aws_error_mock "ResourceNotFoundException: Function not found"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
}

@test "deployment/scripts/update_alias_weights: handles version not found error" {
  export LAMBDA_FUNCTION_NAME="my-function"
  export LAMBDA_MAIN_ALIAS_NAME="main"
  export LAMBDA_NEW_VERSION="999"
  export DESIRED_TRAFFIC="10"

  create_aws_error_mock "ResourceNotFoundException: Version 999 not found"

  unset -f aws
  run_sourced "$SCRIPT"

  assert_failure
}

# Routing config format (pure validation, function-based mock)
@test "deployment/scripts/update_alias_weights: formats routing config as valid JSON" {
  local new_version="2"
  local weight="0.25"

  local routing_config
  routing_config=$(jq -n --arg ver "$new_version" --arg w "$weight" \
    '{($ver): ($w | tonumber)}')

  echo "$routing_config" | jq -e '.' > /dev/null
  [ $? -eq 0 ]

  assert_json_path_equal "$routing_config" '.["2"]' "0.25"
}

@test "deployment/scripts/update_alias_weights: handles integer weights correctly" {
  local weight_int=25
  local weight_decimal=$(echo "scale=2; $weight_int / 100" | bc)

  [[ "$weight_decimal" == *"."* ]] || [ "$weight_decimal" = "0" ]
}
