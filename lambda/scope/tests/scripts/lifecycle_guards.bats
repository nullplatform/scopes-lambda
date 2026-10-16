#!/usr/bin/env bats
# Guards that must behave differently per lifecycle phase, plus step failure paths.
# Scripts are sourced here, as the engine does.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  export NP_OUTPUT_DIR="$BATS_TEST_TMPDIR"

  PROVIDERS_JSON='{"results":[{"category":"cloud-providers","attributes":{"account":{"id":"111122223333","region":"us-east-1"}}},{"category":"scope-configurations","attributes":{"state":{"tofu_state_bucket":"np-state"}}}]}'

  export CONTEXT='{"scope":{"id":"scope-1","slug":"api","nrn":"organization=1:account=2:namespace=3:application=4:scope=5","capabilities":{"visibility":"private","architecture":"arm64","deployment_type":"docker-image"}},"namespace":{"slug":"ns"},"application":{"slug":"app"},"account":{"slug":"acc"}}'

  unset LAMBDA_PUBLIC_EXPOSURE
}

teardown() {
  teardown_test_env
}

run_build_context() {
  source "$LAMBDA_DIR/scope/build_context"
}

run_resolve_placeholder_image() {
  source "$LAMBDA_DIR/utils/log"
  source "$LAMBDA_DIR/scope/scripts/resolve_placeholder_image"
}

run_fetch_scope_configuration() {
  source "$LAMBDA_DIR/utils/log"
  source "$LAMBDA_DIR/utils/fetch_scope_configuration"
}

# printenv only sees exported variables.
run_fetch_scope_configuration_exports() {
  run_fetch_scope_configuration || return $?
  echo "TOFU_STATE_BUCKET_REGION=$(printenv TOFU_STATE_BUCKET_REGION)"
  echo "AWS_REGION=$(printenv AWS_REGION)"
}

# The marker would only print if the step returned; with `exit` it never runs.
run_assume_role_step() {
  source "$LAMBDA_DIR/utils/assume_role_step"
  local rc=$?
  echo "STEP_RETURNED_${rc}_CALLER_ALIVE"
  return $rc
}

@test "build_context: private scopes are routed through an ALB" {
  export LOG_LEVEL=debug
  mock_np "$PROVIDERS_JSON"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_success
  assert_line "📋 Function: scope-1-app-api | Visibility: private"
  assert_output_contains "networking_mode=alb"
}

@test "build_context: an unknown visibility fails closed instead of going public" {
  mock_np "$PROVIDERS_JSON"
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "partner"')
  export TOFU_ACTION="apply"

  run run_build_context

  assert_failure
  assert_line "❌ Invalid networking for visibility 'partner' (public exposure 'invalid')"
  assert_line '🔧 How to fix:'
  assert_line "   • Use visibility 'public' or 'private'"
  assert_line "   • Set networking.public_exposure (scope-configurations) or LAMBDA_PUBLIC_EXPOSURE to 'alb' or 'api_gateway'"
}

@test "build_context: internal visibility is treated as private" {
  mock_np "$PROVIDERS_JSON"
  export LOG_LEVEL=debug
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "internal"')
  export TOFU_ACTION="apply"

  run run_build_context

  assert_success
  assert_output_contains "networking_mode=alb"
  assert_line "📋 Function: scope-1-app-api | Visibility: private"
}

@test "build_context: the scopes-networking override blocks an apply" {
  mock_np "$PROVIDERS_JSON"
  mkdir -p "$BATS_TEST_TMPDIR/networking/lambda/scope/tofu/networking/alb"
  touch "$BATS_TEST_TMPDIR/networking/lambda/scope/tofu/networking/alb/setup"
  export OVERRIDES_PATH="$BATS_TEST_TMPDIR/networking/lambda"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_failure
  assert_line "❌ The networking override at $BATS_TEST_TMPDIR/networking/lambda is no longer supported"
  assert_line '💡 Possible causes:'
  assert_line '   The agent still runs the scopes-networking Lambda override, which networking now replaces'
  assert_line '🔧 How to fix:'
  assert_line '   • Disable overrides on the agent (overrides_enabled = false) and re-run the action'
  assert_line '   • Existing scopes keep their ALB rule: the next create or update adopts it'
}

@test "build_context: the scopes-networking override does not block a destroy" {
  mock_np "$PROVIDERS_JSON"
  mkdir -p "$BATS_TEST_TMPDIR/networking/lambda/scope/tofu/networking/alb"
  touch "$BATS_TEST_TMPDIR/networking/lambda/scope/tofu/networking/alb/setup"
  export OVERRIDES_PATH="other/path, $BATS_TEST_TMPDIR/networking/lambda"
  export TOFU_ACTION="destroy"

  run run_build_context

  assert_success
}

@test "build_context: overrides without networking are allowed" {
  mock_np "$PROVIDERS_JSON"
  mkdir -p "$BATS_TEST_TMPDIR/other/scope/workflows"
  export OVERRIDES_PATH="$BATS_TEST_TMPDIR/other"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_success
}

@test "build_context: an invalid public exposure blocks an apply" {
  mock_np "$PROVIDERS_JSON"
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "public"')
  export LAMBDA_PUBLIC_EXPOSURE="cloudfront"
  export TOFU_ACTION="apply"

  run run_build_context

  assert_failure
  assert_line "❌ Invalid networking for visibility 'public' (public exposure 'cloudfront')"
  assert_line '🔧 How to fix:'
  assert_line "   • Use visibility 'public' or 'private'"
  assert_line "   • Set networking.public_exposure (scope-configurations) or LAMBDA_PUBLIC_EXPOSURE to 'alb' or 'api_gateway'"
  assert_output_not_contains "Scope context built successfully"
}

@test "build_context: an invalid public exposure does not block a destroy" {
  mock_np "$PROVIDERS_JSON"
  export CONTEXT=$(echo "$CONTEXT" | jq '.scope.capabilities.visibility = "public"')
  export LAMBDA_PUBLIC_EXPOSURE="cloudfront"
  export TOFU_ACTION="destroy"

  run run_build_context

  assert_success
  assert_line "✨ Scope context built successfully"
}

@test "fetch_scope_configuration: surfaces an np failure instead of an empty config" {
  # np prints its errors to stdout, not stderr, and exits non-zero.
  np() { echo '{ "error": "connection refused" }'; return 1; }

  run run_fetch_scope_configuration

  assert_failure
  assert_line "🔑 Fetching scope configuration..."
  assert_line "❌ Failed to fetch providers for NRN=organization=1:account=2:namespace=3:application=4:scope=5"
  assert_line "💡 Possible causes:"
  assert_line "   - The nullplatform API is unreachable or returned an error"
  assert_line "   - The agent's API key lacks permission to list providers"
  assert_line "🔧 How to fix:"
  assert_line "   • Verify the agent can reach the nullplatform API"
  assert_line "   • Check the agent's credentials and NRN visibility"
  assert_line '   📋 Error: { "error": "connection refused" } '
  assert_output_not_contains "Scope configuration fetched successfully"
}

@test "resolve_placeholder_image: an unconfigured placeholder aborts an Image scope" {
  export PACKAGE_TYPE="Image"
  unset PLACEHOLDER_IMAGE_URI

  run run_resolve_placeholder_image

  assert_failure
  assert_line "❌ No placeholder image is configured for this scope"
  assert_line "💡 Possible causes:"
  assert_line "   • deployment.placeholder_image_uri is unset on the scope-configurations provider"
  assert_line "   • PLACEHOLDER_IMAGE_URI_DEFAULT is unset on the agent"
  assert_line "🔧 How to fix:"
  assert_line "   • Publish one to your private ECR: lambda/scope/placeholder/publish"
  assert_output_not_contains "Placeholder image resolved"
}

@test "resolve_placeholder_image: a public placeholder aborts an Image scope" {
  export PACKAGE_TYPE="Image"
  export PLACEHOLDER_IMAGE_URI="public.ecr.aws/nullplatform/aws-lambda/placeholder:latest"

  run run_resolve_placeholder_image

  assert_failure
  assert_line "❌ Placeholder image is public, and Lambda cannot pull it: public.ecr.aws/nullplatform/aws-lambda/placeholder:latest"
  assert_line "💡 Possible causes:"
  assert_line "   • PLACEHOLDER_IMAGE_URI points at a public ECR registry"
  assert_line "🔧 How to fix:"
  assert_line "   • Publish one to your private ECR: lambda/scope/placeholder/publish"
  assert_output_not_contains "Placeholder image resolved"
}

@test "resolve_placeholder_image: a failed lookup reports the parsed URI and the AWS error" {
  export PACKAGE_TYPE="Image"
  export PLACEHOLDER_IMAGE_URI="084420143809.dkr.ecr.us-east-1.amazonaws.com/prd-registry-cross-account:placeholder"
  mock_aws_error "An error occurred (RepositoryNotFoundException) when calling the DescribeImages operation"

  run run_resolve_placeholder_image

  assert_failure
  assert_line "   📋 registry=084420143809 region=us-east-1 repo=prd-registry-cross-account tag=placeholder"
  assert_line "❌ Placeholder image not found: 084420143809.dkr.ecr.us-east-1.amazonaws.com/prd-registry-cross-account:placeholder"
  assert_line "📋 Parsed: registry=084420143809 region=us-east-1 repo=prd-registry-cross-account tag=placeholder"
  assert_line "📋 Error details: An error occurred (RepositoryNotFoundException) when calling the DescribeImages operation "
  assert_output_not_contains "Placeholder image resolved"
}

@test "resolve_placeholder_image: the lookup targets the registry the URI names" {
  export PACKAGE_TYPE="Image"
  export PLACEHOLDER_IMAGE_URI="084420143809.dkr.ecr.us-east-1.amazonaws.com/prd-registry-cross-account:placeholder"
  # Only answers when the caller asks the URI's registry, not the caller's own.
  aws() {
    case "$*" in
      *"--registry-id 084420143809"*) echo '{"imageDetails":[{"imageTags":["placeholder"]}]}' ;;
      *) echo "An error occurred (RepositoryNotFoundException) ... registry with id '684909421940'" >&2; return 1 ;;
    esac
  }

  run run_resolve_placeholder_image

  assert_success
  assert_line "✨ Placeholder image resolved: 084420143809.dkr.ecr.us-east-1.amazonaws.com/prd-registry-cross-account:placeholder"
  assert_output_not_contains "Placeholder image not found"
}

@test "fetch_scope_configuration: exports the optional state bucket region" {
  np() { echo '{"results":[{"category":"cloud-providers","attributes":{"account":{"id":"111122223333","region":"us-west-2"}}},{"category":"scope-configurations","attributes":{"state":{"tofu_state_bucket":"np-state","tofu_state_bucket_region":"us-east-1"}}}]}'; }

  run run_fetch_scope_configuration_exports

  assert_success
  assert_line "TOFU_STATE_BUCKET_REGION=us-east-1"
  assert_line "AWS_REGION=us-west-2"
}

run_fetch_listeners() {
  run_fetch_scope_configuration || return $?
  echo "PUBLIC=$(printenv ALB_PUBLIC_LISTENER_ARNS)"
  echo "PRIVATE=$(printenv ALB_PRIVATE_LISTENER_ARNS)"
}

@test "fetch_scope_configuration: listener lists come from scope-configurations first" {
  np() { echo '{"results":[{"category":"cloud-providers","attributes":{"account":{"region":"us-east-1"}}},{"category":"vpc","attributes":{"load_balancer":{"public":{"listener_arn":"arn:vpc-public"},"private":{"listener_arn":"arn:vpc-private"}}}},{"category":"scope-configurations","attributes":{"networking":{"alb_public_listener_arns":["arn:a","arn:b"]}}}]}'; }

  run run_fetch_listeners

  assert_success
  assert_line "PUBLIC=arn:a,arn:b"
  assert_line "PRIVATE=arn:vpc-private"
}

@test "fetch_scope_configuration: no listeners configured exports empty lists" {
  np() { echo '{"results":[{"category":"cloud-providers","attributes":{"account":{"region":"us-east-1"}}}]}'; }

  run run_fetch_listeners

  assert_success
  assert_line "PUBLIC="
  assert_line "PRIVATE="
}

@test "fetch_scope_configuration: an empty result set names the missing providers" {
  np() { echo '{"results":[]}'; }

  run run_fetch_scope_configuration

  assert_failure
  assert_line "❌ No providers found for NRN=organization=1:account=2:namespace=3:application=4:scope=5"
  assert_line "💡 Possible causes:"
  assert_line "   - The NRN has no vpc, cloud-providers or scope-configurations provider configured"
  assert_line "   - The scope dimensions match no provider: dimensions=none"
  assert_line "🔧 How to fix:"
  assert_line "   • Configure the providers on the NRN or a parent of it"
  assert_output_not_contains "Scope configuration fetched successfully"
}

@test "build_context: a missing CONTEXT reports itself, not a failed provider fetch" {
  unset CONTEXT

  run run_build_context

  assert_failure
  assert_line "❌ CONTEXT variable is not set or empty"
  assert_line "💡 Possible causes:"
  assert_line "   The agent was invoked without the required CONTEXT payload"
  assert_line "🔧 How to fix:"
  assert_line "   • Ensure the scope event includes a valid CONTEXT JSON"
  assert_line "   • Verify the agent trigger is passing CONTEXT correctly"
  assert_output_not_contains "Failed to fetch providers"
}

@test "assume_role_step: a failed assume-role aborts the step" {
  export ASSUME_ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda"
  mock_aws_error "AccessDenied: User is not authorized to perform sts:AssumeRole"

  run run_assume_role_step

  assert_failure
  assert_line "   🔑 Assuming role: arn:aws:iam::111122223333:role/np-lambda"
  assert_line "ERROR: sts:AssumeRole failed for arn:aws:iam::111122223333:role/np-lambda"
  assert_line "AccessDenied: User is not authorized to perform sts:AssumeRole"
  assert_line "❌ assume_role step failed: could not assume arn:aws:iam::111122223333:role/np-lambda"
  assert_line "💡 Possible causes:"
  assert_line "   - The agent's pod role is not allowed to sts:AssumeRole the target role"
  assert_line "   - The target role's trust policy does not trust the agent role"
  assert_line "   - The resolved ARN is wrong (check the IAM provider selector=lambda)"
  assert_output_not_contains "CALLER_ALIVE"
}
