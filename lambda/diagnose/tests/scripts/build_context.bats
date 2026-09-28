#!/usr/bin/env bats

setup() {
  load "helpers/diagnose_helper.bash"
  setup_diagnose_env
  SCRIPT="$LAMBDA_DIR/diagnose/build_context"
  mock_aws_cmd lambda get-function '{"Configuration":{"FunctionArn":"arn:aws:lambda:us-east-1:123:function:fn","Role":"arn:aws:iam::123:role/r"}}'
}

run_build_context() {
  run bash -c "source '$SCRIPT' && echo \"DOMAIN=\$SCOPE_DOMAIN ALIAS=\$LAMBDA_MAIN_ALIAS_NAME ROLE=\$LAMBDA_ROLE_ARN\""
}

@test "diagnose/build_context: reads the domain from the scope" {
  export CONTEXT='{"scope":{"id":"s-1","slug":"my-scope","domain":"my-scope.example.com"},"application":{"slug":"my-app"}}'

  run_build_context

  assert_success
  assert_output_contains "DOMAIN=my-scope.example.com "
  assert_output_contains "ROLE=arn:aws:iam::123:role/r"
}

@test "diagnose/build_context: leaves the domain empty when the scope has none" {
  export CONTEXT='{"scope":{"id":"s-1","slug":"my-scope"},"application":{"slug":"my-app"}}'

  run_build_context

  assert_success
  assert_output_contains "DOMAIN= "
}

@test "diagnose/build_context: defaults LAMBDA_MAIN_ALIAS_NAME to main" {
  export CONTEXT='{"scope":{"id":"s-1","slug":"my-scope"},"application":{"slug":"my-app"}}'

  run_build_context

  assert_output_contains "ALIAS=main "
}

@test "diagnose/build_context: keeps a configured LAMBDA_MAIN_ALIAS_NAME" {
  export CONTEXT='{"scope":{"id":"s-1","slug":"my-scope"},"application":{"slug":"my-app"}}'
  export LAMBDA_MAIN_ALIAS_NAME="live"

  run_build_context

  assert_output_contains "ALIAS=live "
}

@test "diagnose/build_context: fails without a scope id" {
  export CONTEXT='{}'

  run_build_context

  assert_failure
  assert_output_contains "Failed to extract scope ID from CONTEXT"
}
