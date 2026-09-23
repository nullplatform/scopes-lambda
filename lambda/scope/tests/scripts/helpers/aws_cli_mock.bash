#!/bin/bash
# AWS CLI mock keyed by "<service> <subcommand>", for scripts that branch on
# what AWS returns. Unlike the sequential queue in test_helper.bash it also
# records calls, so a test can assert one did NOT happen.
#
#   setup_aws_cli_mock
#   aws_mock_response "lambda get-policy" 254 'ResourceNotFoundException'
#   aws_mock_response "lambda update-function-configuration" 254 'err' 2  # first 2 calls
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

exit_code=$(sed -n '1p' "$response_file")
remaining=$(sed -n '2p' "$response_file")
output=$(tail -n +3 "$response_file")

# A bounded response expires, so later calls fall through to the default.
if [ -n "$remaining" ]; then
  if [ "$remaining" -le 1 ]; then
    rm -f "$response_file"
  else
    printf '%s\n%s\n%s\n' "$exit_code" "$((remaining - 1))" "$output" > "$response_file"
  fi
fi

if [ "$exit_code" != "0" ]; then
  printf '%s\n' "$output" >&2
  exit "$exit_code"
fi

printf '%s\n' "$output"
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

# aws_mock_response "<service> <subcommand>" <exit_code> [output] [times]
aws_mock_response() {
  local key="${1// /_}"
  local exit_code="$2"
  local output="${3:-}"
  local times="${4:-}"
  printf '%s\n%s\n%s\n' "$exit_code" "$times" "$output" > "$MOCK_BIN_DIR/resp_${key}"
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
