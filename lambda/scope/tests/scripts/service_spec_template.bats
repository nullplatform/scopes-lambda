#!/usr/bin/env bats
# Renders service-spec.json.tpl with gomplate and checks the default, option
# order, UI selector and input validation driven by LAMBDA_DEPLOYMENT_TYPES.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TEMPLATE="$(cd "$TEST_DIR/../../../specs" && pwd)/service-spec.json.tpl"
  # Spec rendered without LAMBDA_DEPLOYMENT_TYPES. Regenerate on intentional spec changes:
  #   NRN="organization=1:account=2" gomplate -f lambda/specs/service-spec.json.tpl > <this file>
  DEFAULT_FIXTURE="$TEST_DIR/fixtures/service-spec.default.json"
  export NRN="organization=1:account=2"
  unset LAMBDA_DEPLOYMENT_TYPES

  if ! command -v gomplate >/dev/null 2>&1; then
    skip "gomplate not installed"
  fi
}

render() {
  gomplate -f "$TEMPLATE"
}

prop() {
  # prop <jq path under attributes.schema.properties>
  echo "$output" | jq -c ".attributes.schema.properties.$1"
}

selector_count() {
  echo "$output" | jq '[.attributes.schema.uiSchema.elements[] | select(.scope == "#/properties/deployment_type")] | length'
}

@test "service spec: default renders valid JSON with both deployment types, docker-image first" {
  run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(prop 'deployment_type.default')" = '"docker-image"' ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"docker-image","title":"Docker Image (ECR)"},{"const":"zip","title":"ZIP Package (S3)"}]' ]
  [ "$(prop 'asset_type.default')" = '"docker-image"' ]
  [ "$(selector_count)" = '1' ]
}

@test "service spec: unset and docker-image,zip render exactly the pinned default spec" {
  local expected
  expected="$(cat "$DEFAULT_FIXTURE")"
  run render
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  LAMBDA_DEPLOYMENT_TYPES="docker-image,zip" run render
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "service spec: empty LAMBDA_DEPLOYMENT_TYPES behaves as the default" {
  LAMBDA_DEPLOYMENT_TYPES="" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.default')" = '"docker-image"' ]
  [ "$(prop 'deployment_type.oneOf | length')" = '2' ]
  [ "$(selector_count)" = '1' ]
}

@test "service spec: zip only defaults to zip, hides the selector and keeps docker-image valid" {
  LAMBDA_DEPLOYMENT_TYPES="zip" run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(prop 'deployment_type.default')" = '"zip"' ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"zip","title":"ZIP Package (S3)"},{"const":"docker-image","title":"Docker Image (ECR)"}]' ]
  [ "$(prop 'asset_type.default')" = '"lambda"' ]
  [ "$(selector_count)" = '0' ]
}

@test "service spec: docker-image only hides the selector and keeps zip valid" {
  LAMBDA_DEPLOYMENT_TYPES="docker-image" run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(prop 'deployment_type.default')" = '"docker-image"' ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"docker-image","title":"Docker Image (ECR)"},{"const":"zip","title":"ZIP Package (S3)"}]' ]
  [ "$(prop 'asset_type.default')" = '"docker-image"' ]
  [ "$(selector_count)" = '0' ]
}

@test "service spec: zip,docker-image defaults to zip and keeps both options in order" {
  LAMBDA_DEPLOYMENT_TYPES="zip,docker-image" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.default')" = '"zip"' ]
  [ "$(prop 'deployment_type.oneOf | map(.const)')" = '["zip","docker-image"]' ]
  [ "$(prop 'asset_type.default')" = '"lambda"' ]
  [ "$(selector_count)" = '1' ]
}

@test "service spec: spaces around list entries are ignored" {
  LAMBDA_DEPLOYMENT_TYPES="zip, docker-image" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.oneOf | map(.const)')" = '["zip","docker-image"]' ]
}

@test "service spec: required list, allOf rules for both types, runtime rule and NRN visibility are unaffected" {
  local value
  for value in "zip" "docker-image" "zip,docker-image"; do
    LAMBDA_DEPLOYMENT_TYPES="$value" run render
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.attributes.schema.required | index("deployment_type")' >/dev/null
    [ "$(echo "$output" | jq -c '[.attributes.schema.allOf[] | [.if.properties.deployment_type.const, .then.properties.asset_type.const]]')" = '[["zip","lambda"],["docker-image","docker-image"]]' ] \
      || { echo "allOf changed for '$value'"; return 1; }
    echo "$output" | jq -e '.attributes.schema.uiSchema.elements[] | select(.scope == "#/properties/runtime") | .rule.condition.schema.const == "zip"' >/dev/null
    [ "$(echo "$output" | jq -r '.visible_to[0]')" = "organization=1:account=2" ]
  done
}

@test "service spec: unknown deployment type fails the render" {
  LAMBDA_DEPLOYMENT_TYPES="zip,container" run render
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown deployment type"* ]]
  [[ "$output" == *"container"* ]]
}

@test "service spec: repeated deployment type fails the render" {
  LAMBDA_DEPLOYMENT_TYPES="zip,zip" run render
  [ "$status" -ne 0 ]
  [[ "$output" == *"repeated deployment type"* ]]
}

@test "service spec: malformed lists fail the render" {
  local value
  for value in "zip," ",zip" "zip,,docker-image" "ZIP" " "; do
    LAMBDA_DEPLOYMENT_TYPES="$value" run render
    [ "$status" -ne 0 ] || { echo "accepted: '$value'"; return 1; }
  done
}
