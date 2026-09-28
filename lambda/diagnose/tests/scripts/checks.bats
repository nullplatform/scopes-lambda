#!/usr/bin/env bats

setup() {
  load "helpers/diagnose_helper.bash"
  setup_diagnose_env
  CHECKS="$LAMBDA_DIR/diagnose/checks"
  export LAMBDA_FUNCTION_NAME="scope-123-my-app-my-scope"
  export CONTEXT='{"scope":{"id":"scope-123","capabilities":{"visibility":"public"}}}'
}

@test "checks: every check fails when LAMBDA_FUNCTION_NAME is empty" {
  unset LAMBDA_FUNCTION_NAME
  export SCOPE_ID="scope-123"
  for check in lambda_exists lambda_active provisioned_concurrency iam_role_valid networking_healthy; do
    run_check "$CHECKS/$check"
    assert_failure
    [ "$(check_status)" = "failed" ]
    [ "$(check_evidence .evidence.summary)" = "No Lambda function found for scope scope-123" ]
  done
}

@test "lambda_exists: success when the function exists" {
  mock_aws_cmd lambda get-function '{"Configuration":{"FunctionName":"x"}}'

  run_check "$CHECKS/lambda_exists"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence .evidence.severity)" = "info" ]
}

@test "lambda_exists: failed when the function is missing" {
  mock_aws_cmd lambda get-function "An error occurred (ResourceNotFoundException)" 254

  run_check "$CHECKS/lambda_exists"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence .evidence.severity)" = "critical" ]
  [ "$(check_evidence '.evidence.affected[0]')" = "$LAMBDA_FUNCTION_NAME" ]
  [ "$(check_evidence '.evidence.suggested_actions | length')" = "3" ]
}

@test "lambda_active: success when State is Active" {
  mock_aws_cmd lambda get-function-configuration '{"State":"Active","LastUpdateStatus":"Successful"}'

  run_check "$CHECKS/lambda_active"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence .evidence.details.state)" = "Active" ]
}

@test "lambda_active: failed when State is not Active" {
  mock_aws_cmd lambda get-function-configuration '{"State":"Failed","LastUpdateStatus":"Failed"}'

  run_check "$CHECKS/lambda_active"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence .evidence.details.state)" = "Failed" ]
}

@test "iam_role_valid: success when the role exists and trusts Lambda" {
  mock_aws_cmd lambda get-function-configuration '{"Role":"arn:aws:iam::123:role/my-role"}'
  mock_aws_cmd iam get-role '{"Role":{"RoleName":"my-role","AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Principal":{"Service":["edgelambda.amazonaws.com","lambda.amazonaws.com"]},"Action":"sts:AssumeRole"}]}}}'

  run_check "$CHECKS/iam_role_valid"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence .evidence.details.role_name)" = "my-role" ]
}

@test "iam_role_valid: failed when the role does not trust Lambda" {
  mock_aws_cmd lambda get-function-configuration '{"Role":"arn:aws:iam::123:role/my-role"}'
  mock_aws_cmd iam get-role '{"Role":{"RoleName":"my-role","AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}}}'

  run_check "$CHECKS/iam_role_valid"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence '.evidence.summary')" = "IAM role 'my-role' does not trust lambda.amazonaws.com" ]
}

@test "iam_role_valid: failed when the role does not exist" {
  mock_aws_cmd lambda get-function-configuration '{"Role":"arn:aws:iam::123:role/my-role"}'
  mock_aws_cmd iam get-role "An error occurred (NoSuchEntity)" 254

  run_check "$CHECKS/iam_role_valid"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence '.evidence.affected[0]')" = "my-role" ]
}

@test "networking_healthy: success when API Gateway may invoke a public function" {
  mock_aws_cmd lambda get-policy '{"Policy":"{\"Principal\":{\"Service\":\"apigateway.amazonaws.com\"}}"}'

  run_check "$CHECKS/networking_healthy"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence .evidence.details.integration)" = "API Gateway" ]
}

@test "networking_healthy: success when a public function sits behind an ALB" {
  mock_aws_cmd lambda get-policy '{"Policy":"{\"Principal\":{\"Service\":\"elasticloadbalancing.amazonaws.com\"}}"}'

  run_check "$CHECKS/networking_healthy"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence .evidence.details.integration)" = "ALB" ]
  grep -q -- "--qualifier main" "$MOCK_BIN_DIR/aws_calls.log"
}

@test "networking_healthy: warning when the main alias has no invoke permission" {
  export CONTEXT='{"scope":{"id":"scope-123","capabilities":{"visibility":"private"}}}'
  mock_aws_cmd lambda get-policy "An error occurred (ResourceNotFoundException)" 254

  run_check "$CHECKS/networking_healthy"

  assert_success
  [ "$(check_status)" = "warning" ]
  [ "$(check_evidence .evidence.details.integration)" = "" ]
}

@test "networking_healthy: skipped when HTTP is disabled" {
  export CONTEXT='{"scope":{"id":"scope-123","capabilities":{"http_enabled":false}}}'

  run_check "$CHECKS/networking_healthy"

  assert_success
  [ "$(check_status)" = "skipped" ]
}

@test "provisioned_concurrency: skipped when not configured" {
  mock_aws_cmd lambda get-provisioned-concurrency-config "An error occurred (ProvisionedConcurrencyConfigNotFoundException)" 254

  run_check "$CHECKS/provisioned_concurrency"

  assert_success
  [ "$(check_status)" = "skipped" ]
}

@test "provisioned_concurrency: success when READY on the configured alias" {
  export LAMBDA_MAIN_ALIAS_NAME="live"
  mock_aws_cmd lambda get-provisioned-concurrency-config '{"Status":"READY","RequestedProvisionedConcurrentExecutions":2,"AllocatedProvisionedConcurrentExecutions":2}'

  run_check "$CHECKS/provisioned_concurrency"

  assert_success
  [ "$(check_status)" = "success" ]
  grep -q -- "--qualifier live" "$MOCK_BIN_DIR/aws_calls.log"
}

@test "provisioned_concurrency: failed when allocation FAILED" {
  mock_aws_cmd lambda get-provisioned-concurrency-config '{"Status":"FAILED","RequestedProvisionedConcurrentExecutions":2,"AllocatedProvisionedConcurrentExecutions":0}'

  run_check "$CHECKS/provisioned_concurrency"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence .evidence.details.allocated)" = "0" ]
}

@test "provisioned_concurrency: warning while IN_PROGRESS" {
  mock_aws_cmd lambda get-provisioned-concurrency-config '{"Status":"IN_PROGRESS","RequestedProvisionedConcurrentExecutions":2,"AllocatedProvisionedConcurrentExecutions":0}'

  run_check "$CHECKS/provisioned_concurrency"

  assert_success
  [ "$(check_status)" = "warning" ]
}

@test "dns_resolves: skipped when no domain is configured" {
  unset SCOPE_DOMAIN

  run_check "$CHECKS/dns_resolves"

  assert_success
  [ "$(check_status)" = "skipped" ]
}

@test "dns_resolves: success when the domain resolves" {
  export SCOPE_DOMAIN="my-scope.example.com"
  mock_bin dig "10.0.0.1"

  run_check "$CHECKS/dns_resolves"

  assert_success
  [ "$(check_status)" = "success" ]
  [ "$(check_evidence '.evidence.details.records[0]')" = "10.0.0.1" ]
}

@test "dns_resolves: failed when the domain does not resolve" {
  export SCOPE_DOMAIN="my-scope.example.com"
  mock_bin dig ""

  run_check "$CHECKS/dns_resolves"

  assert_failure
  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence '.evidence.affected[0]')" = "my-scope.example.com" ]
}

@test "dns_resolves: failed when no DNS server answers" {
  export SCOPE_DOMAIN="my-scope.example.com"
  mock_bin dig ";; communications error to 10.0.0.2#53: timed out" 9

  run_check "$CHECKS/dns_resolves"

  assert_failure
  [ "$(check_status)" = "failed" ]
}
