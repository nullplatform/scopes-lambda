#!/bin/bash
# Shared setup for the diagnose check tests.

DIAGNOSE_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$(cd "$DIAGNOSE_TESTS_DIR/../../.." && pwd)"

source "$LAMBDA_DIR/deployment/tests/scripts/helpers/test_helper.bash"

DIAGNOSE_UTILS="$LAMBDA_DIR/diagnose/utils/diagnose_utils"

setup_diagnose_env() {
  setup_test_env
  unset -f aws np

  export SERVICE_PATH="$LAMBDA_DIR"
  export NP_OUTPUT_DIR="$BATS_TEST_TMPDIR/output"
  export MOCK_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$NP_OUTPUT_DIR/checks" "$MOCK_BIN_DIR"
  export PATH="$MOCK_BIN_DIR:$PATH"

  export SCRIPT_OUTPUT_FILE="$NP_OUTPUT_DIR/checks/check.json"
  export SCRIPT_LOG_FILE="$NP_OUTPUT_DIR/checks/check.log"
  echo '{"name":"Check","category":"Function","status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"
  : > "$SCRIPT_LOG_FILE"

  cat > "$MOCK_BIN_DIR/aws" <<'MOCK'
#!/bin/bash
# Responds per "<service>_<command>" from files written by mock_aws_cmd.
echo "$*" >> "$(dirname "$0")/aws_calls.log"
key="$(dirname "$0")/aws_${1}_${2}"
[ -f "$key.out" ] || { echo "No mock for $1 $2" >&2; exit 1; }
cat "$key.out"
exit "$(cat "$key.rc")"
MOCK
  chmod +x "$MOCK_BIN_DIR/aws"
}

# Usage: mock_aws_cmd <service> <command> <output> [exit_code]
mock_aws_cmd() {
  printf '%s\n' "$3" > "$MOCK_BIN_DIR/aws_${1}_${2}.out"
  echo "${4:-0}" > "$MOCK_BIN_DIR/aws_${1}_${2}.rc"
}

# Usage: mock_bin <name> <output> [exit_code]
mock_bin() {
  printf '#!/bin/bash\necho "$*" >> "%s/%s_calls.log"\nprintf "%%s\\n" %q\nexit %s\n' \
    "$MOCK_BIN_DIR" "$1" "$2" "${3:-0}" > "$MOCK_BIN_DIR/$1"
  chmod +x "$MOCK_BIN_DIR/$1"
}

# Sources a check the way the executor does: in the shell that loaded diagnose_utils.
run_check() {
  run bash -c "source '$DIAGNOSE_UTILS'; source '$1'"
}

check_status() {
  jq -r '.status' "$SCRIPT_OUTPUT_FILE"
}

check_evidence() {
  jq -r "${1:-.evidence}" "$SCRIPT_OUTPUT_FILE"
}
