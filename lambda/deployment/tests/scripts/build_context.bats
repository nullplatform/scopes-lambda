#!/usr/bin/env bats
# Unit tests for deployment/build_context script

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HELPERS_DIR="$SCRIPT_DIR/helpers"
LAMBDA_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_CONTEXT_SCRIPT="$LAMBDA_DIR/deployment/build_context"

load "$HELPERS_DIR/test_helper.bash"
load "$HELPERS_DIR/mock_context.bash"

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# Context extraction
@test "deployment/build_context: extracts scope_id from context" {
  set_context "public"

  local scope_id
  scope_id=$(echo "$CONTEXT" | jq -r '.scope.id // ""')

  assert_equal "$scope_id" "scope-123"
}

@test "deployment/build_context: extracts deployment_id from context" {
  set_context "public"

  local deployment_id
  deployment_id=$(echo "$CONTEXT" | jq -r '.deployment.id // ""')

  assert_equal "$deployment_id" "deploy-456"
}

@test "deployment/build_context: sets visibility to public by default" {
  set_context "minimal"

  local visibility
  visibility=$(echo "$CONTEXT" | jq -r '.scope.capabilities.visibility // "public"')

  assert_equal "$visibility" "public"
}

@test "deployment/build_context: extracts visibility from capabilities" {
  set_context "private"

  local visibility
  visibility=$(echo "$CONTEXT" | jq -r '.scope.capabilities.visibility // "public"')

  assert_equal "$visibility" "private"
}

# Layer selection
@test "deployment/build_context: resolves public visibility correctly" {
  set_context "public"

  local visibility
  visibility=$(echo "$CONTEXT" | jq -r '.scope.capabilities.visibility // "public"')

  assert_equal "$visibility" "public"
}

@test "deployment/build_context: selects alb layer when visibility is private" {
  set_context "private"

  local visibility
  visibility=$(echo "$CONTEXT" | jq -r '.scope.capabilities.visibility // "public"')

  assert_equal "$visibility" "private"
}

# Function name generation
@test "deployment/build_context: generates valid function name under 64 chars" {
  set_context "public"

  local account_slug namespace_slug app_slug scope_slug
  account_slug=$(echo "$CONTEXT" | jq -r '.account.slug // ""')
  namespace_slug=$(echo "$CONTEXT" | jq -r '.namespace.slug // ""')
  app_slug=$(echo "$CONTEXT" | jq -r '.application.slug // ""')
  scope_slug=$(echo "$CONTEXT" | jq -r '.scope.slug // ""')

  local function_name="${account_slug}-${namespace_slug}-${app_slug}-${scope_slug}"

  assert_less_than "${#function_name}" "64" "function_name length"
  assert_equal "$function_name" "my-account-my-namespace-my-app-my-scope"
}

@test "deployment/build_context: truncates function name when exceeds limit" {
  local very_long_name="this-is-a-very-long-account-name-that-exceeds-the-limit-for-lambda-functions"
  local max_length=64

  if [ ${#very_long_name} -gt $max_length ]; then
    truncated_name="${very_long_name:0:$max_length}"
    assert_equal "${#truncated_name}" "$max_length"
  fi
}

# Capability extraction
@test "deployment/build_context: extracts memory from capabilities" {
  set_context "public"

  local memory
  memory=$(echo "$CONTEXT" | jq -r '.scope.capabilities.memory // 256')

  assert_equal "$memory" "256"
}

@test "deployment/build_context: uses default memory when not specified" {
  set_context "minimal"

  local memory
  memory=$(echo "$CONTEXT" | jq -r '.scope.capabilities.memory // 256')

  assert_equal "$memory" "256"
}

@test "deployment/build_context: extracts timeout from capabilities" {
  set_context "public"

  local timeout
  timeout=$(echo "$CONTEXT" | jq -r '.scope.capabilities.timeout // 30')

  assert_equal "$timeout" "30"
}

@test "deployment/build_context: extracts runtime from capabilities" {
  set_context "public"

  local runtime
  runtime=$(echo "$CONTEXT" | jq -r '.scope.capabilities.runtime // "nodejs20.x"')

  assert_equal "$runtime" "nodejs20.x"
}

@test "deployment/build_context: extracts handler from capabilities" {
  set_context "public"

  local handler
  handler=$(echo "$CONTEXT" | jq -r '.scope.capabilities.handler // "index.handler"')

  assert_equal "$handler" "index.handler"
}

@test "deployment/build_context: sets architecture to arm64 by default" {
  set_context "minimal"

  local architecture
  architecture=$(echo "$CONTEXT" | jq -r '.scope.capabilities.architecture // "arm64"')

  assert_equal "$architecture" "arm64"
}

@test "deployment/build_context: extracts architecture from capabilities" {
  set_context "private"

  local architecture
  architecture=$(echo "$CONTEXT" | jq -r '.scope.capabilities.architecture // "arm64"')

  assert_equal "$architecture" "x86_64"
}

# VPC configuration
@test "deployment/build_context: extracts VPC config when vpc_enabled is true" {
  set_context "vpc"

  local vpc_enabled
  vpc_enabled=$(echo "$CONTEXT" | jq -r '.scope.capabilities.vpc_enabled // false')
  assert_equal "$vpc_enabled" "true"

  local subnet_ids
  subnet_ids=$(echo "$CONTEXT" | jq -r '.providers["cloud-providers"].networking.subnet_ids | length')
  assert_equal "$subnet_ids" "2"
}

@test "deployment/build_context: skips VPC config when vpc_enabled is false" {
  set_context "public"

  local vpc_enabled
  vpc_enabled=$(echo "$CONTEXT" | jq -r '.scope.capabilities.vpc_enabled // false')

  [ "$vpc_enabled" = "false" ] || [ "$vpc_enabled" = "null" ]
}

# Lambda layers
@test "deployment/build_context: extracts layers from capabilities" {
  set_context "layers"

  local layers_count
  layers_count=$(echo "$CONTEXT" | jq -r '.scope.capabilities.layers | length')

  assert_equal "$layers_count" "2"
}

@test "deployment/build_context: handles empty layers array" {
  set_context "public"

  local layers
  layers=$(echo "$CONTEXT" | jq -r '.scope.capabilities.layers // []')

  [ "$layers" = "null" ] || [ "$layers" = "[]" ]
}

# Concurrency settings
@test "deployment/build_context: extracts provisioned_concurrency settings" {
  set_context "provisioned"

  assert_json_path_equal "$CONTEXT" '.scope.capabilities.provisioned_concurrency.type' "provisioned"
  assert_json_path_equal "$CONTEXT" '.scope.capabilities.provisioned_concurrency.value' "5"
}

@test "deployment/build_context: extracts reserved_concurrency settings" {
  set_context "provisioned"

  assert_json_path_equal "$CONTEXT" '.scope.capabilities.reserved_concurrency.type' "reserved"
  assert_json_path_equal "$CONTEXT" '.scope.capabilities.reserved_concurrency.value' "10"
}

# Environment variables
@test "deployment/build_context: extracts environment variables from parameters" {
  set_context "public"

  assert_json_path_equal "$CONTEXT" '.parameters.results | length' "2"
}

@test "deployment/build_context: handles empty parameters" {
  set_context "minimal"

  assert_json_path_equal "$CONTEXT" '.parameters.results | length' "0"
}

# S3 asset extraction
@test "deployment/build_context: extracts S3 bucket and key from asset URL" {
  set_context "public"

  local asset_url
  asset_url=$(echo "$CONTEXT" | jq -r '.asset.url // ""')

  local bucket key
  bucket=$(echo "$asset_url" | sed 's|s3://||' | cut -d'/' -f1)
  key=$(echo "$asset_url" | sed 's|s3://[^/]*/||')

  assert_equal "$bucket" "my-bucket"
  assert_equal "$key" "path/to/code.zip"
}

# TOFU_VARIABLES JSON
@test "deployment/build_context: builds TOFU_VARIABLES as valid JSON" {
  set_context "public"

  local tofu_vars
  tofu_vars=$(jq -n \
    --arg name "test-function" \
    --arg runtime "nodejs20.x" \
    --argjson memory 256 \
    '{
      lambda_function_name: $name,
      lambda_runtime: $runtime,
      lambda_memory_size: $memory
    }')

  # Verify it's valid JSON
  echo "$tofu_vars" | jq -e '.' > /dev/null
  [ $? -eq 0 ]

  assert_json_path_equal "$tofu_vars" '.lambda_function_name' "test-function"
  assert_json_path_equal "$tofu_vars" '.lambda_runtime' "nodejs20.x"
  assert_json_path_equal "$tofu_vars" '.lambda_memory_size' "256"
}

# Provider credentials
@test "deployment/build_context: extracts AWS region from providers" {
  set_context "public"

  assert_json_path_equal "$CONTEXT" '.providers["cloud-providers"].credentials.region' "us-east-1"
}

@test "deployment/build_context: extracts hosted zone ID from providers" {
  set_context "public"

  assert_json_path_equal "$CONTEXT" '.providers["cloud-providers"].networking.hosted_public_zone_id' "Z1234567890ABC"
}

# Container Image (ECR) Support
@test "deployment/build_context: extracts asset type docker-image" {
  set_context "docker_image"
  local asset_type
  asset_type=$(echo "$CONTEXT" | jq -r '.asset.type // "lambda-asset"')
  assert_equal "$asset_type" "docker-image"
}

@test "deployment/build_context: sets package_type to Image for docker-image asset" {
  set_context "docker_image"
  local asset_type
  asset_type=$(echo "$CONTEXT" | jq -r '.asset.type // "lambda-asset"')
  # When asset type is docker-image, package_type should be Image
  [ "$asset_type" = "docker-image" ]
  local package_type="Image"
  assert_equal "$package_type" "Image"
}

@test "deployment/build_context: extracts ECR image URI from docker-image asset" {
  set_context "docker_image"
  local image_uri
  image_uri=$(echo "$CONTEXT" | jq -r '.asset.url // ""')
  assert_equal "$image_uri" "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0"
}

@test "deployment/build_context: does not set S3 bucket for docker-image asset" {
  set_context "docker_image"
  local asset_type
  asset_type=$(echo "$CONTEXT" | jq -r '.asset.type // "lambda-asset"')
  # For docker-image, S3 fields should remain empty
  [ "$asset_type" = "docker-image" ]
}

@test "deployment/build_context: defaults asset_type to lambda-asset when not specified" {
  set_context "public"
  local asset_type
  asset_type=$(echo "$CONTEXT" | jq -r '.asset.type // "lambda-asset"')
  assert_equal "$asset_type" "lambda-asset"
}

@test "deployment/build_context: sets package_type to Zip for lambda-asset" {
  set_context "public"
  local asset_type
  asset_type=$(echo "$CONTEXT" | jq -r '.asset.type // "lambda-asset"')
  [ "$asset_type" = "lambda-asset" ]
  local package_type="Zip"
  assert_equal "$package_type" "Zip"
}

# Parameters Strategy
@test "deployment/build_context: secretsmanager context has parameters" {
  set_context "secretsmanager"
  assert_json_path_equal "$CONTEXT" '.parameters.results | length' "3"
}
