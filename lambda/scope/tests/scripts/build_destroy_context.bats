#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  TMP_OUTPUT_DIR="$(mktemp -d)"
  export OUTPUT_DIR="$TMP_OUTPUT_DIR"
  export SCOPE_ID="scope-123"
  export LAMBDA_FUNCTION_NAME="np-lambda-test-fn"
  export CONTEXT='{}'
}

teardown() {
  rm -rf "$TMP_OUTPUT_DIR"
  teardown_test_env
}

# Sourced, as the runner does — it also keeps the aws mock visible to the script.
run_build_destroy_context() {
  source "$LAMBDA_DIR/scope/scripts/build_destroy_context"
  echo "RESULT package_type=$PACKAGE_TYPE image_uri=$IMAGE_URI s3_bucket=$S3_BUCKET s3_key=$S3_KEY"
}

run_setup_compute() {
  source "$LAMBDA_DIR/scope/tofu/compute/lambda/setup"
}

@test "build_destroy_context: function already gone does not inherit PACKAGE_TYPE=Image" {
  mock_aws_error "An error occurred (ResourceNotFoundException) when calling the GetFunction operation"
  export PACKAGE_TYPE="Image"

  run run_build_destroy_context

  assert_success
  assert_output_contains "Lambda function not found in AWS"
  assert_output_contains "package_type=Zip"
  assert_output_contains "s3_bucket=destroy-placeholder"
  assert_output_contains "s3_key=destroy-placeholder"
}

@test "build_destroy_context: image function passes its image URI through" {
  mock_aws '{"Configuration":{"PackageType":"Image"},"Code":{"ImageUri":"1234.dkr.ecr.us-east-1.amazonaws.com/app:v1"}}'

  run run_build_destroy_context

  assert_success
  assert_output_contains "package_type=Image"
  assert_output_contains "image_uri=1234.dkr.ecr.us-east-1.amazonaws.com/app:v1"
}

@test "build_destroy_context: image function without an image URI falls back to a sentinel" {
  mock_aws '{"Configuration":{"PackageType":"Image"},"Code":{}}'

  run run_build_destroy_context

  assert_success
  assert_output_contains "package_type=Image"
  assert_output_contains "image_uri=destroy-placeholder"
}

@test "build_destroy_context: zip function exports the zip placeholders" {
  mock_aws '{"Configuration":{"PackageType":"Zip"},"Code":{}}'

  run run_build_destroy_context

  assert_success
  assert_output_contains "package_type=Zip"
  assert_output_contains "s3_bucket=destroy-placeholder"
}

@test "build_destroy_context: an unexpected AWS error is logged and the destroy still proceeds" {
  mock_aws_error "An error occurred (AccessDeniedException) when calling the GetFunction operation"

  run run_build_destroy_context

  assert_success
  assert_output_contains "Could not read the Lambda function"
  assert_output_contains "AccessDeniedException"
  assert_output_contains "package_type=Zip"
}

@test "compute/lambda/setup: destroy skips asset validation" {
  export CONTEXT='{"lambda":{"function_name":"np-lambda-test-fn"},"scope":{"id":"scope-123"},"deployment":{"id":"deploy-1"}}'
  export TOFU_VARIABLES='{}'
  export MODULES_TO_USE=""
  export TOFU_ACTION="destroy"
  export PACKAGE_TYPE="Image"
  export IMAGE_URI=""

  run run_setup_compute

  assert_success
  assert_output_contains "Lambda compute configured successfully"
}

@test "compute/lambda/setup: apply still rejects an empty image URI" {
  export CONTEXT='{"lambda":{"function_name":"np-lambda-test-fn"},"scope":{"id":"scope-123"},"deployment":{"id":"deploy-1"}}'
  export TOFU_VARIABLES='{}'
  export MODULES_TO_USE=""
  export TOFU_ACTION="apply"
  export PACKAGE_TYPE="Image"
  export IMAGE_URI=""

  run run_setup_compute

  assert_failure
  assert_output_contains "PACKAGE_TYPE=Image but IMAGE_URI is empty"
}
