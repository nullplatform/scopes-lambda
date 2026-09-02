#!/bin/bash
# AWS CLI mock keyed by "<service> <subcommand>", for scripts that branch on
# what AWS returns. Unlike the sequential queue in test_helper.bash it also
# records calls, so a test can assert one did NOT happen.
#
#   setup_aws_cli_mock
#   aws_mock_response "lambda get-policy" 254 'ResourceNotFoundException'
#   assert_aws_cli_not_called "add-permission"
#
# Unconfigured subcommands succeed empty, so best-effort calls need no stub.

setup_aws_cli_mock() {
  : "${MOCK_BIN_DIR:?setup_aws_cli_mock requires MOCK_BIN_DIR}"
  : > "$MOCK_BIN_DIR/aws_calls"

  cat > "$MOCK_BIN_DIR/aws" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
printf '%s\n' "$*" >> "$MOCK_DIR/aws_calls"

response_file="$MOCK_DIR/resp_${1}_${2}"
[ -f "$response_file" ] || exit 0

exit_code=$(head -1 "$response_file")
output=$(tail -n +2 "$response_file")

if [ "$exit_code" != "0" ]; then
  printf '%s\n' "$output" >&2
  exit "$exit_code"
fi

printf '%s\n' "$output"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# aws_mock_response "<service> <subcommand>" <exit_code> [output]
aws_mock_response() {
  local key="${1// /_}"
  local exit_code="$2"
  local output="${3:-}"
  printf '%s\n%s\n' "$exit_code" "$output" > "$MOCK_BIN_DIR/resp_${key}"
}

aws_cli_calls() {
  cat "$MOCK_BIN_DIR/aws_calls" 2>/dev/null
}

assert_aws_cli_called() {
  local pattern="$1"
  if ! grep -qF -- "$pattern" "$MOCK_BIN_DIR/aws_calls" 2>/dev/null; then
    echo "Expected an AWS CLI call containing: $pattern"
    echo "Actual calls:"
    aws_cli_calls | sed 's/^/  - aws /'
    return 1
  fi
}

assert_aws_cli_not_called() {
  local pattern="$1"
  if grep -qF -- "$pattern" "$MOCK_BIN_DIR/aws_calls" 2>/dev/null; then
    echo "Expected NO AWS CLI call containing: $pattern, but found:"
    grep -F -- "$pattern" "$MOCK_BIN_DIR/aws_calls" | sed 's/^/  - aws /'
    return 1
  fi
}

assert_aws_cli_call_count() {
  local pattern="$1" expected="$2" actual
  actual=$(grep -cF -- "$pattern" "$MOCK_BIN_DIR/aws_calls" 2>/dev/null || true)
  if [ "${actual:-0}" != "$expected" ]; then
    echo "Expected $expected AWS CLI call(s) containing '$pattern', got ${actual:-0}"
    aws_cli_calls | sed 's/^/  - aws /'
    return 1
  fi
}
