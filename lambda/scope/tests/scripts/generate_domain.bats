#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock
  aws_mock_response "route53 get-hosted-zone" 0 '{"HostedZone":{"Name":"example.com."}}'

  export NETWORKING_MODE="alb"
  export VISIBILITY="private"
  export HOSTED_PUBLIC_ZONE_ID="ZPUBLIC"
  export HOSTED_PRIVATE_ZONE_ID="ZPRIVATE"
  export NAMESPACE_SLUG="ns"
  export APPLICATION_SLUG="app"
  export SCOPE_SLUG="api"
  export ACCOUNT_SLUG="acc"
  export USE_ACCOUNT_SLUG="false"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

run_generate_domain() {
  source "$LAMBDA_DIR/scope/scripts/generate_domain" || return $?
  echo "RESULT domain=$SCOPE_DOMAIN zone=$DNS_HOSTED_ZONE_ID"
}

@test "generate_domain: private scopes use the private zone" {
  run run_generate_domain

  assert_success
  assert_line "RESULT domain=ns-app-api.example.com zone=ZPRIVATE"
  assert_aws_cli_called "route53 get-hosted-zone --id ZPRIVATE"
}

@test "generate_domain: private scopes fall back to the public zone" {
  export HOSTED_PRIVATE_ZONE_ID=""

  run run_generate_domain

  assert_success
  assert_line "RESULT domain=ns-app-api.example.com zone=ZPUBLIC"
}

@test "generate_domain: public scopes use the public zone" {
  export VISIBILITY="public"

  run run_generate_domain

  assert_success
  assert_line "RESULT domain=ns-app-api.example.com zone=ZPUBLIC"
}

@test "generate_domain: adds the account slug when enabled" {
  export USE_ACCOUNT_SLUG="true"

  run run_generate_domain

  assert_success
  assert_output_contains "RESULT domain=ns-app-api.acc.example.com"
}

@test "generate_domain: an ALB scope without a hosted zone fails" {
  export HOSTED_PRIVATE_ZONE_ID=""
  export HOSTED_PUBLIC_ZONE_ID=""

  run run_generate_domain

  assert_failure
  assert_line '❌ No hosted zone configured for a private scope behind an ALB'
  assert_line '💡 Possible causes:'
  assert_line '   The ALB routes by host header, so the scope needs a domain'
  assert_line '🔧 How to fix:'
  assert_line '   • Set networking.hosted_public_zone_id (and hosted_zone_id for private scopes) in the cloud-providers provider'
}

@test "generate_domain: API Gateway without a hosted zone keeps no domain" {
  export NETWORKING_MODE="api_gateway"
  export VISIBILITY="public"
  export HOSTED_PUBLIC_ZONE_ID=""

  run run_generate_domain

  assert_success
  assert_line "RESULT domain= zone="
}

@test "generate_domain: fails when the hosted zone cannot be read" {
  aws_mock_response "route53 get-hosted-zone" 254 'NoSuchHostedZone'

  run run_generate_domain

  assert_failure
  assert_line "❌ Failed to fetch Route 53 hosted zone 'ZPRIVATE'"
  assert_line '💡 Possible causes:'
  assert_line '   - Invalid hosted zone ID'
  assert_line '   - Missing route53:GetHostedZone permission'
  assert_line '🔧 How to fix:'
  assert_line '   • Verify the hosted zone IDs in the cloud-providers provider'
  assert_line '   📋 AWS error: NoSuchHostedZone'
}

@test "generate_domain: fails on a DNS label over 63 characters" {
  export APPLICATION_SLUG="an-application-slug-long-enough-to-overflow-a-single-dns-label"

  run run_generate_domain

  assert_failure
  assert_line "❌ Domain label 'ns-an-application-slug-long-enough-to-overflow-a-single-dns-label-api' exceeds 63 characters"
  assert_line '🔧 How to fix:'
  assert_line '   • Shorten the namespace, application or scope slug'
}

@test "generate_domain: does nothing without HTTP exposure" {
  export NETWORKING_MODE="none"

  run run_generate_domain

  assert_success
  assert_line "RESULT domain= zone="
  assert_aws_cli_not_called "get-hosted-zone"
}
