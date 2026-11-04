#!/usr/bin/env bats
# Renders service-spec.json.tpl with gomplate and checks the visibility default,
# canonicalization and validation driven by DEFAULT_VISIBILITY.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TEMPLATE="$(cd "$TEST_DIR/../../../specs" && pwd)/service-spec.json.tpl"
  # Same pinned render as service_spec_template.bats: DEFAULT_VISIBILITY unset must not change it.
  DEFAULT_FIXTURE="$TEST_DIR/fixtures/service-spec.default.json"
  export NRN="organization=1:account=2"
  unset LAMBDA_DEPLOYMENT_TYPES DEFAULT_VISIBILITY

  if ! command -v gomplate >/dev/null 2>&1; then
    skip "gomplate not installed"
  fi
}

render() {
  gomplate -f "$TEMPLATE"
}

visibility() {
  # visibility <jq path under attributes.schema.properties.visibility>
  echo "$output" | jq -c ".attributes.schema.properties.visibility.$1"
}

without_default() {
  jq -S 'del(.attributes.schema.properties.visibility.default)'
}

@test "service spec: unset DEFAULT_VISIBILITY defaults to public and keeps both options" {
  run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(visibility default)" = '"public"' ]
  [ "$(visibility oneOf)" = '[{"const":"public","title":"Public"},{"const":"private","title":"Private"}]' ]
}

@test "service spec: unset DEFAULT_VISIBILITY renders exactly the pinned default spec" {
  local expected
  expected="$(cat "$DEFAULT_FIXTURE")"
  run render
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "service spec: empty and public (any case or spacing) render the same spec as unset" {
  local value expected
  expected="$(render)"
  for value in "" "  " public Public " PUBLIC "; do
    DEFAULT_VISIBILITY="$value" run render
    [ "$status" -eq 0 ] || { echo "render failed for '$value': $output"; return 1; }
    [ "$output" = "$expected" ] || { echo "'$value' differs from the unset render"; return 1; }
  done
}

@test "service spec: private and internal (any case or spacing) only change the visibility default" {
  local value expected
  expected="$(render | without_default)"
  for value in private Private " PRIVATE " internal Internal " INTERNAL "; do
    DEFAULT_VISIBILITY="$value" run render
    [ "$status" -eq 0 ] || { echo "render failed for '$value': $output"; return 1; }
    [ "$(visibility default)" = '"private"' ] || { echo "'$value': default $(visibility default)"; return 1; }
    [ "$(echo "$output" | without_default)" = "$expected" ] || { echo "'$value' changes more than the default"; return 1; }
  done
}

@test "service spec: every accepted value renders a default listed in oneOf" {
  local value
  for value in unset public private internal; do
    if [ "$value" = unset ]; then run render; else DEFAULT_VISIBILITY="$value" run render; fi
    [ "$status" -eq 0 ] || { echo "render failed for '$value': $output"; return 1; }
    echo "$output" | jq -e '.attributes.schema.properties.visibility | .default as $d | [.oneOf[].const] | index($d) != null' >/dev/null \
      || { echo "'$value': default $(visibility default) not in oneOf"; return 1; }
  done
}

@test "service spec: DEFAULT_VISIBILITY and LAMBDA_DEPLOYMENT_TYPES are independent" {
  DEFAULT_VISIBILITY=private LAMBDA_DEPLOYMENT_TYPES=zip run render
  [ "$status" -eq 0 ]
  [ "$(visibility default)" = '"private"' ]
  [ "$(echo "$output" | jq -c '.attributes.schema.properties.deployment_type.default')" = '"zip"' ]
}

@test "service spec: unknown DEFAULT_VISIBILITY fails the render instead of guessing" {
  local value
  for value in publik privat intern foo "public,private" "main account"; do
    DEFAULT_VISIBILITY="$value" run render
    [ "$status" -ne 0 ] || { echo "accepted: '$value'"; return 1; }
    [[ "$output" == *"DEFAULT_VISIBILITY: unknown visibility"* ]] || { echo "'$value' message: $output"; return 1; }
    [[ "$output" == *"$value"* ]] || { echo "'$value' missing from: $output"; return 1; }
    [[ "$output" == *"allowed: public, private, internal"* ]] || { echo "'$value' allowed values missing: $output"; return 1; }
  done
}
