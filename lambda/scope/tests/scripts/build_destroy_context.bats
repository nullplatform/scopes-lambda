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
  export NP_OUTPUT_DIR="$TMP_OUTPUT_DIR"
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
  source "$LAMBDA_DIR/scope/scripts/build_destroy_context" || return $?
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
  assert_line "🔍 Building Tofu destroy context..."
  assert_line "   📡 Looking up Lambda function..."
  assert_line "   ⚠️  Lambda function not found in AWS — Tofu will destroy resources from state"
  assert_line "✨ Destroy context built: function=np-lambda-test-fn, package_type=Zip"
  assert_line "RESULT package_type=Zip image_uri= s3_bucket=destroy-placeholder s3_key=destroy-placeholder"
}

@test "build_destroy_context: image function passes its image URI through" {
  mock_aws '{"Configuration":{"PackageType":"Image"},"Code":{"ImageUri":"1234.dkr.ecr.us-east-1.amazonaws.com/app:v1"}}'

  run run_build_destroy_context

  assert_success
  assert_line "✨ Destroy context built: function=np-lambda-test-fn, package_type=Image"
  assert_line "RESULT package_type=Image image_uri=1234.dkr.ecr.us-east-1.amazonaws.com/app:v1 s3_bucket= s3_key="
}

@test "build_destroy_context: image function without an image URI falls back to a sentinel" {
  mock_aws '{"Configuration":{"PackageType":"Image"},"Code":{}}'

  run run_build_destroy_context

  assert_success
  assert_line "RESULT package_type=Image image_uri=destroy-placeholder s3_bucket= s3_key="
}

@test "build_destroy_context: zip function exports the zip placeholders" {
  mock_aws '{"Configuration":{"PackageType":"Zip"},"Code":{}}'

  run run_build_destroy_context

  assert_success
  assert_line "✨ Destroy context built: function=np-lambda-test-fn, package_type=Zip"
  assert_line "RESULT package_type=Zip image_uri= s3_bucket=destroy-placeholder s3_key=destroy-placeholder"
}

@test "build_destroy_context: an AccessDenied on the lookup aborts the destroy" {
  mock_aws_error "An error occurred (AccessDeniedException) when calling the GetFunction operation"

  run run_build_destroy_context

  assert_failure
  assert_line "   ❌ Failed to read the Lambda function 'np-lambda-test-fn'"
  assert_line "  🔒 Permission denied calling lambda:GetFunction"
  assert_line "  💡 Possible causes:"
  assert_line "    • The assumed role is missing lambda:GetFunction"
  assert_line "    • A permissions boundary or SCP is blocking the call"
  assert_line "  🔧 How to fix:"
  assert_line "    • Review the role's policy (see lambda/prerequisites.md)"
  assert_line "   Aborting: cannot confirm the function state in AWS."
  assert_output_not_contains "RESULT"
}

@test "build_destroy_context: any other AWS error also aborts the destroy" {
  mock_aws_error "An error occurred (ThrottlingException) when calling the GetFunction operation"

  run run_build_destroy_context

  assert_failure
  assert_line "   ❌ Failed to read the Lambda function 'np-lambda-test-fn'"
  assert_line "  📋 Error details:"
  assert_line "    An error occurred (ThrottlingException) when calling the GetFunction operation "
  assert_line "   Aborting: cannot confirm the function state in AWS."
  assert_output_not_contains "🔒 Permission denied calling lambda:GetFunction"
  assert_output_not_contains "RESULT"
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
  assert_line "🔍 Validating Lambda compute configuration..."
  assert_line "   ✅ asset validation skipped (tofu destroy reads resources from state)"
  assert_line "   📡 Building Lambda configuration..."
  assert_line "✨ Lambda compute configured successfully"
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
  assert_line "   ❌ Image URI not found (PACKAGE_TYPE=Image but IMAGE_URI is empty)" 
  assert_line "  💡 Possible causes:"
  assert_line "    • No placeholder image is configured for this account"
  assert_line "    • The scope's Lambda function could not be read from AWS"
  assert_line "  🔧 How to fix:"
  assert_line "    • Set deployment.placeholder_image_uri in the scope-configurations provider"
  assert_line "    • Or set PLACEHOLDER_IMAGE_URI_DEFAULT on the agent (README: Placeholder Image)"
  assert_output_not_contains "Lambda compute configured successfully"
}
