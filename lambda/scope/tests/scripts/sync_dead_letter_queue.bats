#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HELPERS_DIR="$TEST_DIR/helpers"
  LAMBDA_DIR="$(cd "$TEST_DIR/../../.." && pwd)"

  load "$HELPERS_DIR/test_helper.bash"
  load "$HELPERS_DIR/aws_cli_mock.bash"

  setup_test_env
  export SERVICE_PATH="$LAMBDA_DIR"
  SCRIPT="$LAMBDA_DIR/scope/scripts/sync_dead_letter_queue"

  MOCK_BIN_DIR="$(mktemp -d)"
  export PATH="$MOCK_BIN_DIR:$PATH"
  unset -f aws np
  setup_aws_cli_mock

  export LAMBDA_FUNCTION_NAME="my-test-function"
  export SCOPE_ID="9001"
  export DLQ_UPDATE_RETRY_DELAY_SECONDS=0
  ROLE_ARN="arn:aws:iam::111122223333:role/np-lambda-my-test-function-role"
}

teardown() {
  teardown_test_env
  [ -d "$MOCK_BIN_DIR" ] && rm -rf "$MOCK_BIN_DIR"
}

context_with_dlq() {
  export CONTEXT="{\"scope\":{\"capabilities\":{\"dead_letter_target_arn\":\"$1\",\"dead_letter_kms_key_arn\":\"${2:-}\"}}}"
}

function_with_dlq() {
  local current="${1:-}"
  local dlq_block="null"
  [ -n "$current" ] && dlq_block="{\"TargetArn\":\"$current\"}"
  aws_mock_response "lambda get-function-configuration" 0 \
    "{\"FunctionArn\":\"arn:aws:lambda:us-east-1:111122223333:function:my-test-function\",\"Role\":\"$ROLE_ARN\",\"DeadLetterConfig\":$dlq_block}"
}

@test "sync_dead_letter_queue: sets an SQS target and grants sqs:SendMessage on it only" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "iam put-role-policy"
  assert_aws_cli_called "sqs:SendMessage"
  assert_aws_cli_called "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  assert_aws_cli_called "--dead-letter-config TargetArn=arn:aws:sqs:us-east-1:111122223333:my-dlq"
  assert_aws_cli_called "--role-name np-lambda-my-test-function-role"
}

@test "sync_dead_letter_queue: grants sns:Publish for an SNS target" {
  context_with_dlq "arn:aws:sns:us-east-1:111122223333:my-topic"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "sns:Publish"
  assert_aws_cli_not_called "sqs:SendMessage"
}

@test "sync_dead_letter_queue: grants access before enabling the queue" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  # Lambda drops failed events if the role cannot write yet, so the grant has
  # to land first.
  grant_line=$(grep -n "iam put-role-policy" "$MOCK_BIN_DIR/aws_calls" | cut -d: -f1)
  enable_line=$(grep -n "dead-letter-config TargetArn=" "$MOCK_BIN_DIR/aws_calls" | cut -d: -f1)
  [ "$grant_line" -lt "$enable_line" ]
}

@test "sync_dead_letter_queue: is idempotent when the target is already set" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_step

  assert_success
  assert_aws_cli_called "iam put-role-policy"
  assert_aws_cli_not_called "update-function-configuration"
  assert_output_contains "up to date"
}

@test "sync_dead_letter_queue: clears the config and the grant when the ARN is empty" {
  context_with_dlq ""
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_step

  assert_success
  assert_aws_cli_called '--dead-letter-config {"TargetArn":""}'
  assert_aws_cli_called "iam delete-role-policy"
  assert_aws_cli_called "--policy-name np-lambda-dlq-9001"
  assert_output_contains "Dead letter queue disabled"
}

@test "sync_dead_letter_queue: does not call Lambda when there is nothing to disable" {
  context_with_dlq ""
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_not_called "update-function-configuration"
  assert_aws_cli_called "iam delete-role-policy"
}

@test "sync_dead_letter_queue: rejects a target that is neither SQS nor SNS" {
  context_with_dlq "arn:aws:s3:::my-bucket"
  function_with_dlq

  run_step

  assert_failure
  assert_output_contains "Unsupported dead letter target"
  assert_aws_cli_not_called "update-function-configuration"
}

@test "sync_dead_letter_queue: rejects a queue name that is not an ARN" {
  context_with_dlq "my-dlq"
  function_with_dlq

  run_step

  assert_failure
  assert_output_contains "Unsupported dead letter target"
}

@test "sync_dead_letter_queue: never touches code, environment or version" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_not_called "update-function-code"
  assert_aws_cli_not_called "--environment"
  assert_aws_cli_not_called "publish-version"
}

@test "sync_dead_letter_queue: fails when LAMBDA_FUNCTION_NAME is not set" {
  unset LAMBDA_FUNCTION_NAME
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_step

  assert_failure
  assert_output_contains "LAMBDA_FUNCTION_NAME is required"
}

@test "sync_dead_letter_queue: surfaces a failure reading the function" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  aws_mock_response "lambda get-function-configuration" 254 "ResourceNotFoundException"

  run_step

  assert_failure
  assert_output_contains "Failed to read configuration"
}

@test "sync_dead_letter_queue: surfaces a denied IAM grant without enabling the queue" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "iam put-role-policy" 254 "AccessDenied"

  run_step

  assert_failure
  assert_output_contains "Failed to grant dead letter access"
  assert_aws_cli_not_called "update-function-configuration"
}

@test "sync_dead_letter_queue: scopes the policy name so shared roles do not collide" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  # A dedicated execution role can be shared between scopes; an unscoped name
  # would let one scope overwrite or delete another's grant.
  assert_aws_cli_called "--policy-name np-lambda-dlq-9001"
}

@test "sync_dead_letter_queue: fails when SCOPE_ID is not set" {
  unset SCOPE_ID
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_failure
  assert_output_contains "SCOPE_ID is required"
}

@test "sync_dead_letter_queue: fails when the update does not complete" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "lambda wait" 255 "Waiter FunctionUpdated failed"

  run_step

  assert_failure
  assert_output_contains "did not complete"
}

@test "sync_dead_letter_queue: removes the grant when enabling fails" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "lambda update-function-configuration" 254 "InvalidParameterValueException"

  run_step

  assert_failure
  # Otherwise the role keeps send access to an arbitrary ARN with no DLQ enabled
  assert_aws_cli_called "iam delete-role-policy"
}

@test "sync_dead_letter_queue: restores the previous grant when a change fails" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:new-dlq"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:old-dlq"
  aws_mock_response "lambda update-function-configuration" 254 "InvalidParameterValueException"

  run_step

  assert_failure
  assert_aws_cli_called "old-dlq"
  assert_aws_cli_not_called "iam delete-role-policy"
}

PROPAGATION_ERROR="An error occurred (InvalidParameterValueException) when calling the UpdateFunctionConfiguration operation: The provided execution role does not have permissions to call SendMessage on SQS"

@test "sync_dead_letter_queue: retries until the role grant propagates" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "lambda update-function-configuration" 254 "$PROPAGATION_ERROR" 2

  run_step

  assert_success
  assert_aws_cli_call_count "--dead-letter-config TargetArn=arn:aws:sqs:us-east-1:111122223333:my-dlq" 3
  assert_aws_cli_not_called "iam delete-role-policy"
}

@test "sync_dead_letter_queue: gives up after the retry budget and reverts the grant" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  export DLQ_UPDATE_MAX_ATTEMPTS=3
  aws_mock_response "lambda update-function-configuration" 254 "$PROPAGATION_ERROR"

  run_step

  assert_failure
  assert_aws_cli_call_count "--dead-letter-config TargetArn=arn:aws:sqs:us-east-1:111122223333:my-dlq" 3
  assert_output_contains "has not propagated yet"
  assert_aws_cli_called "iam delete-role-policy"
}

@test "sync_dead_letter_queue: does not retry an error unrelated to propagation" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  aws_mock_response "lambda update-function-configuration" 254 "ResourceConflictException: update in progress"

  run_step

  assert_failure
  assert_aws_cli_call_count "--dead-letter-config TargetArn=arn:aws:sqs:us-east-1:111122223333:my-dlq" 1
}

@test "sync_dead_letter_queue: names the grant statement so it is identifiable in audit logs" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "npLambdaDeadLetter"
}

KMS_KEY="arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"

@test "sync_dead_letter_queue: grants nothing on KMS when the target is not encrypted" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "npLambdaDeadLetter"
  assert_aws_cli_not_called "kms:GenerateDataKey"
  assert_aws_cli_not_called "npLambdaDeadLetterKms"
}

@test "sync_dead_letter_queue: grants the KMS key alongside the send permission" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq" "$KMS_KEY"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "npLambdaDeadLetterKms"
  assert_aws_cli_called "kms:GenerateDataKey"
  assert_aws_cli_called "kms:Decrypt"
  assert_aws_cli_called "$KMS_KEY"
  # The send grant still names the queue, not the key
  assert_aws_cli_called "arn:aws:sqs:us-east-1:111122223333:my-dlq"
}

@test "sync_dead_letter_queue: grants KMS for an SNS target too" {
  context_with_dlq "arn:aws:sns:us-east-1:111122223333:my-topic" "$KMS_KEY"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_called "sns:Publish"
  assert_aws_cli_called "kms:GenerateDataKey"
}

@test "sync_dead_letter_queue: rejects a KMS key that is not an ARN" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq" "1234abcd-12ab-34cd-56ef-1234567890ab"
  function_with_dlq

  run_step

  assert_failure
  assert_output_contains "Unsupported dead letter KMS key"
  # Rejected before anything reaches the role
  assert_aws_cli_not_called "iam put-role-policy"
}

@test "sync_dead_letter_queue: ignores a KMS key when there is no target" {
  context_with_dlq "" "$KMS_KEY"
  function_with_dlq

  run_step

  assert_success
  assert_aws_cli_not_called "kms:GenerateDataKey"
}

@test "sync_dead_letter_queue: restores the captured grant verbatim, KMS included" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:new-dlq" "$KMS_KEY"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:old-dlq"
  aws_mock_response "iam get-role-policy" 0 \
    '{"Statement":[{"Sid":"npLambdaDeadLetter","Action":["sqs:SendMessage"],"Resource":"arn:aws:sqs:us-east-1:111122223333:old-dlq"},{"Sid":"npLambdaDeadLetterKms","Action":["kms:GenerateDataKey"],"Resource":"arn:aws:kms:us-east-1:111122223333:key/OLDKEY"}]}'
  aws_mock_response "lambda update-function-configuration" 254 "InvalidParameterValueException"

  run_step

  assert_failure
  # The previous KMS key comes back, which regenerating the document could not do
  assert_aws_cli_called "OLDKEY"
  assert_aws_cli_not_called "iam delete-role-policy"
}

SERVED_SHA="c2VydmVkLWNvZGU="

alias_serves() {
  local routing="${2:-null}"
  aws_mock_response "lambda get-alias" 0 \
    "{\"Name\":\"main\",\"FunctionVersion\":\"$1\",\"RoutingConfig\":$routing}"
}

served_version_has_dlq() {
  local dlq_block="null"
  [ -n "${1:-}" ] && dlq_block="{\"TargetArn\":\"$1\"}"
  aws_mock_response "lambda get-function" 0 \
    "{\"Configuration\":{\"Version\":\"1\",\"CodeSha256\":\"$SERVED_SHA\",\"DeadLetterConfig\":$dlq_block}}"
}

@test "sync_dead_letter_queue: moves the alias to a version that carries the new queue" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 0 '{"Version":"2"}'

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📝 Granting sqs:SendMessage on the dead letter target to np-lambda-my-test-function-role..."
  assert_line "   📡 Setting dead letter queue to arn:aws:sqs:us-east-1:111122223333:my-dlq..."
  assert_line "   📡 Publishing a version with the dead letter queue for alias 'main' (serves 1)..."
  assert_line "   ✅ Alias 'main' now serves version 2"
  assert_line "✨ Dead letter queue set to arn:aws:sqs:us-east-1:111122223333:my-dlq for my-test-function"
  assert_aws_cli_called "--qualifier main"
  # Pinned to the served code so a rolled-back alias is never rolled forward
  assert_aws_cli_called "--code-sha256 $SERVED_SHA"
  # Deployments find their version by description, which must not be inherited
  assert_aws_cli_called "--description np-scope-dead-letter-queue"
  assert_aws_cli_called "update-alias --function-name my-test-function --name main --function-version 2"
}

@test "sync_dead_letter_queue: moves a lagging alias even when \$LATEST is up to date" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 0 '{"Version":"2"}'

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📝 Granting sqs:SendMessage on the dead letter target to np-lambda-my-test-function-role..."
  assert_line "   📡 Publishing a version with the dead letter queue for alias 'main' (serves 1)..."
  assert_line "   ✅ Alias 'main' now serves version 2"
  assert_line "✨ Dead letter queue up to date for my-test-function"
  assert_aws_cli_not_called "update-function-configuration"
  assert_aws_cli_called "--function-version 2"
}

@test "sync_dead_letter_queue: moves the alias off a version that still has a removed queue" {
  context_with_dlq ""
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  alias_serves 1
  served_version_has_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  aws_mock_response "lambda publish-version" 0 '{"Version":"2"}'

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📝 Removing dead letter queue..."
  assert_line "   📡 Publishing a version with the dead letter queue for alias 'main' (serves 1)..."
  assert_line "   ✅ Alias 'main' now serves version 2"
  assert_line "✨ Dead letter queue disabled for my-test-function"
  assert_aws_cli_called "--function-version 2"
}

@test "sync_dead_letter_queue: leaves the alias alone when its version already matches" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  alias_serves 3
  served_version_has_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📝 Granting sqs:SendMessage on the dead letter target to np-lambda-my-test-function-role..."
  assert_line "✨ Dead letter queue up to date for my-test-function"
  assert_aws_cli_not_called "publish-version"
  assert_aws_cli_not_called "update-alias"
}

@test "sync_dead_letter_queue: does not break a traffic split in progress" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1 '{"AdditionalVersionWeights":{"2":0.1}}'
  served_version_has_dlq

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📡 Setting dead letter queue to arn:aws:sqs:us-east-1:111122223333:my-dlq..."
  assert_line "   ⚠️  Alias 'main' is splitting traffic — the dead letter queue reaches it on the next deployment"
  assert_line "✨ Dead letter queue set to arn:aws:sqs:us-east-1:111122223333:my-dlq for my-test-function"
  assert_aws_cli_not_called "publish-version"
  assert_aws_cli_not_called "update-alias"
}

@test "sync_dead_letter_queue: does not roll the alias forward onto different code" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 254 \
    "An error occurred (PreconditionFailedException) when calling the PublishVersion operation: CodeSha256 does not match"

  run_step

  assert_success
  assert_line "🔍 Reconciling function dead letter queue..."
  assert_line "   📡 Publishing a version with the dead letter queue for alias 'main' (serves 1)..."
  assert_line "   ⚠️  \$LATEST runs other code than alias 'main' — the dead letter queue reaches it on the next deployment"
  assert_line "✨ Dead letter queue set to arn:aws:sqs:us-east-1:111122223333:my-dlq for my-test-function"
  assert_aws_cli_not_called "update-alias"
}

@test "sync_dead_letter_queue: fails when the version cannot be published" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 254 "AccessDeniedException"

  run_step

  assert_failure
  assert_output_contains "Failed to publish a version for alias 'main'"
  assert_aws_cli_not_called "update-alias"
}

@test "sync_dead_letter_queue: fails when the alias cannot be moved" {
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 0 '{"Version":"2"}'
  aws_mock_response "lambda update-alias" 254 "AccessDeniedException"

  run_step

  assert_failure
  assert_output_contains "Failed to move alias 'main' to version 2"
}

@test "sync_dead_letter_queue: honours a custom main alias name" {
  export LAMBDA_MAIN_ALIAS_NAME="live"
  context_with_dlq "arn:aws:sqs:us-east-1:111122223333:my-dlq"
  function_with_dlq
  alias_serves 1
  served_version_has_dlq
  aws_mock_response "lambda publish-version" 0 '{"Version":"2"}'

  run_step

  assert_success
  assert_aws_cli_called "get-alias --function-name my-test-function --name live"
  assert_aws_cli_called "--name live --function-version 2"
}
