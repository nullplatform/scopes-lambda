#!/usr/bin/env bats
# Renders service-spec.json.tpl with gomplate and checks the deployment_type
# options driven by LAMBDA_DEPLOYMENT_TYPES.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TEMPLATE="$(cd "$TEST_DIR/../../../specs" && pwd)/service-spec.json.tpl"
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

@test "service spec: default renders valid JSON with both deployment types, docker-image first" {
  run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(prop 'deployment_type.default')" = '"docker-image"' ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"docker-image","title":"Docker Image (ECR)"},{"const":"zip","title":"ZIP Package (S3)"}]' ]
  [ "$(prop 'asset_type.default')" = '"docker-image"' ]
}

@test "service spec: empty LAMBDA_DEPLOYMENT_TYPES behaves as the default" {
  LAMBDA_DEPLOYMENT_TYPES="" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.default')" = '"docker-image"' ]
  [ "$(prop 'deployment_type.oneOf | length')" = '2' ]
}

@test "service spec: zip only offers one option, defaults to zip and asset_type lambda" {
  LAMBDA_DEPLOYMENT_TYPES="zip" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.default')" = '"zip"' ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"zip","title":"ZIP Package (S3)"}]' ]
  [ "$(prop 'asset_type.default')" = '"lambda"' ]
}

@test "service spec: docker-image only offers one option and keeps asset_type docker-image" {
  LAMBDA_DEPLOYMENT_TYPES="docker-image" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.oneOf')" = '[{"const":"docker-image","title":"Docker Image (ECR)"}]' ]
  [ "$(prop 'asset_type.default')" = '"docker-image"' ]
}

@test "service spec: zip,docker-image defaults to zip and keeps both options in order" {
  LAMBDA_DEPLOYMENT_TYPES="zip,docker-image" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.default')" = '"zip"' ]
  [ "$(prop 'deployment_type.oneOf | map(.const)')" = '["zip","docker-image"]' ]
  [ "$(prop 'asset_type.default')" = '"lambda"' ]
}

@test "service spec: spaces around list entries are ignored" {
  LAMBDA_DEPLOYMENT_TYPES="zip, docker-image" run render
  [ "$status" -eq 0 ]
  [ "$(prop 'deployment_type.oneOf | map(.const)')" = '["zip","docker-image"]' ]
}

@test "service spec: required list, allOf rules and NRN visibility are unaffected" {
  LAMBDA_DEPLOYMENT_TYPES="zip" run render
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.attributes.schema.required | index("deployment_type")' >/dev/null
  [ "$(echo "$output" | jq '.attributes.schema.allOf | length')" = '2' ]
  [ "$(echo "$output" | jq -r '.visible_to[0]')" = "organization=1:account=2" ]
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
