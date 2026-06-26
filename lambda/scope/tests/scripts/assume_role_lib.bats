#!/usr/bin/env bats
# Unit tests for the pure resolution functions in utils/assume_role_lib.
#
# arn_for_selector_from_json is pure jq — exercised directly.
# provider_arn_for_selector orchestrates `np provider list` -> `np provider read`;
# we stub np() branching on its arguments (stateless, so it survives the
# command-substitution subshells the function uses) instead of a sequential mock.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"

  # Stub np branching on args; FAKE_NP_MODE tweaks the `provider list` result.
  np() {
    local args="$*"
    case "$args" in
      *"provider list"*)
        if [ "${FAKE_NP_MODE:-}" = "no_provider" ]; then
          echo '{"results":[]}'
        else
          echo '{"results":[{"id":"prov-123"}]}'
        fi
        ;;
      *"provider read"*)
        echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"my-scope","arn":"arn:aws:iam::123456789012:role/test-lambda-role"}]}}}'
        ;;
      *) echo '{}' ;;
    esac
  }
  export -f np

  source "$LAMBDA_DIR/utils/assume_role_lib"
}

# --- arn_for_selector_from_json (pure) -------------------------------------

JSON='{"attributes":{"iam_role_arns":{"arns":[{"selector":"s3","arn":"arn:aws:iam::111:role/s3"},{"selector":"lambda","arn":"arn:aws:iam::111:role/lambda"}]}}}'

@test "arn_for_selector_from_json: matching selector returns its arn" {
  run arn_for_selector_from_json "$JSON" lambda
  assert_success
  [ "$output" = "arn:aws:iam::111:role/lambda" ]
}

@test "arn_for_selector_from_json: unknown selector returns empty" {
  run arn_for_selector_from_json "$JSON" ecs
  assert_success
  [ -z "$output" ]
}

@test "arn_for_selector_from_json: missing arns key returns empty" {
  run arn_for_selector_from_json '{"attributes":{}}' s3
  assert_success
  [ -z "$output" ]
}

@test "arn_for_selector_from_json: empty input returns empty" {
  run arn_for_selector_from_json '' s3
  assert_success
  [ -z "$output" ]
}

@test "arn_for_selector_from_json: malformed json returns empty" {
  run arn_for_selector_from_json 'not json' s3
  assert_success
  [ -z "$output" ]
}

@test "arn_for_selector_from_json: empty selector returns empty" {
  run arn_for_selector_from_json "$JSON" ''
  assert_success
  [ -z "$output" ]
}

@test "arn_for_selector_from_json: duplicate selector takes first" {
  local dup='{"attributes":{"iam_role_arns":{"arns":[{"selector":"s3","arn":"first"},{"selector":"s3","arn":"second"}]}}}'
  run arn_for_selector_from_json "$dup" s3
  assert_success
  [ "$output" = "first" ]
}

# --- provider_arn_for_selector (np list -> read orchestration) -------------

@test "provider_arn_for_selector: resolves arn for matching selector" {
  run provider_arn_for_selector "organization=1:account=2" my-scope
  assert_success
  [ "$output" = "arn:aws:iam::123456789012:role/test-lambda-role" ]
}

@test "provider_arn_for_selector: no provider instance returns empty" {
  export FAKE_NP_MODE=no_provider
  run provider_arn_for_selector "organization=1:account=2" my-scope
  assert_success
  [ -z "$output" ]
}

@test "provider_arn_for_selector: selector not in provider returns empty" {
  run provider_arn_for_selector "organization=1:account=2" does-not-exist
  assert_success
  [ -z "$output" ]
}

@test "provider_arn_for_selector: empty nrn returns empty" {
  run provider_arn_for_selector "" my-scope
  assert_success
  [ -z "$output" ]
}

@test "provider_arn_for_selector: empty selector returns empty" {
  run provider_arn_for_selector "organization=1:account=2" ""
  assert_success
  [ -z "$output" ]
}

# --- resolve_assume_role_arn (full precedence chain) -----------------------
# Each test defines its own stateless np stub (branches on args) so it survives
# the command-substitution subshells the resolver uses.

@test "resolve_assume_role_arn: env override wins over everything" {
  export ASSUME_ROLE_ARN="arn:env"
  run resolve_assume_role_arn "organization=1:account=2" lambda
  assert_success
  [ "$output" = "arn:env" ]
}

@test "resolve_assume_role_arn: IAM provider when no env override" {
  np() {
    case "$*" in
      *"--specification_slug aws-iam-configuration"*) echo '{"results":[{"id":"iam-1"}]}' ;;
      *"provider read"*) echo '{"attributes":{"iam_role_arns":{"arns":[{"selector":"lambda","arn":"arn:provider:lambda"}]}}}' ;;
      *) echo '{}' ;;
    esac
  }
  export -f np
  run resolve_assume_role_arn "organization=1:account=2" lambda
  assert_success
  [ "$output" = "arn:provider:lambda" ]
}

@test "resolve_assume_role_arn: scope-config fallback when provider misses" {
  np() {
    case "$*" in
      *"--specification_slug aws-iam-configuration"*) echo '{"results":[]}' ;;
      *"--categories scope-configurations"*) echo '{"results":[{"attributes":{"assume_role":{"arn":"arn:scopecfg:legacy"}}}]}' ;;
      *) echo '{}' ;;
    esac
  }
  export -f np
  run resolve_assume_role_arn "organization=1:account=2" lambda
  assert_success
  [ "$output" = "arn:scopecfg:legacy" ]
}

@test "resolve_assume_role_arn: ASSUME_ROLE_ARN_DEFAULT when nothing else resolves" {
  np() { echo '{"results":[]}'; }
  export -f np
  export ASSUME_ROLE_ARN_DEFAULT="arn:default"
  run resolve_assume_role_arn "organization=1:account=2" lambda
  assert_success
  [ "$output" = "arn:default" ]
}

@test "resolve_assume_role_arn: empty (IRSA) when nothing resolves and no default" {
  np() { echo '{"results":[]}'; }
  export -f np
  run resolve_assume_role_arn "organization=1:account=2" lambda
  assert_success
  [ -z "$output" ]
}
