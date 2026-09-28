#!/usr/bin/env bats

setup() {
  load "helpers/diagnose_helper.bash"
  setup_diagnose_env
  source "$DIAGNOSE_UTILS"
  export NP_ACTION_CONTEXT='{"notification":{"id":"action-1","service":{"id":"service-1"}}}'

  # Keep a copy of the body: notify_results deletes it after the call.
  cat > "$MOCK_BIN_DIR/np" <<'MOCK'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/np_calls.log"
while [ $# -gt 0 ]; do
  [ "$1" = "--body" ] && cp "$2" "$(dirname "$0")/np_body.json"
  shift
done
MOCK
  chmod +x "$MOCK_BIN_DIR/np"
}

@test "evidence_json: builds the evidence schema" {
  run evidence_json "summary" "warning" '["fn"]' '{"a":1}' '["do it"]'

  assert_success
  [ "$(echo "$output" | jq -c .)" = '{"summary":"summary","severity":"warning","affected":["fn"],"details":{"a":1},"suggested_actions":["do it"]}' ]
}

@test "update_check_result: writes status, evidence and log tail" {
  echo "some log line" > "$SCRIPT_LOG_FILE"

  update_check_result --status "failed" --evidence '{"summary":"broken"}'

  [ "$(check_status)" = "failed" ]
  [ "$(check_evidence .evidence.summary)" = "broken" ]
  [ "$(check_evidence '.logs[0]')" = "some log line" ]
  [ "$(check_evidence '.end_at')" != "null" ]
}

@test "update_check_result: running sets start_at" {
  update_check_result --status "running" --evidence '{}'

  [ "$(check_status)" = "running" ]
  [ "$(check_evidence '.start_at')" != "null" ]
}

@test "update_check_result: rejects invalid evidence" {
  run update_check_result --status "success" --evidence 'not-json'

  assert_failure
  [ "$(check_status)" = "pending" ]
}

@test "notify_check_running: marks the current check running" {
  source "$LAMBDA_DIR/diagnose/notify_check_running"

  [ "$(check_status)" = "running" ]
}

@test "notify_results: patches the action with checks grouped by category" {
  echo '{"name":"A","category":"Function","status":"success"}' > "$NP_OUTPUT_DIR/checks/a.json"
  echo '{"name":"B","category":"Networking","status":"failed"}' > "$NP_OUTPUT_DIR/checks/b.json"
  rm "$NP_OUTPUT_DIR/checks/check.json"
  mkdir -p "$NP_OUTPUT_DIR/data" && echo '{}' > "$NP_OUTPUT_DIR/data/ignored.json"

  run source "$LAMBDA_DIR/diagnose/notify_results"

  assert_success
  grep -q -- "service action patch --id action-1 --serviceId service-1 --body .*\.json --no-output" "$MOCK_BIN_DIR/np_calls.log"
  body="$MOCK_BIN_DIR/np_body.json"
  [ "$(jq -r '.results.categories | map(.category) | join(",")' "$body")" = "Function,Networking" ]
  [ "$(jq -r '.results.categories[0].summary.success' "$body")" = "1" ]
  [ "$(jq -r '.results.categories[1].summary.failed' "$body")" = "1" ]
  [ "$(jq -r '.results.categories[1].checks[0].name' "$body")" = "B" ]
}

@test "notify_results: fails without result files" {
  rm -f "$NP_OUTPUT_DIR/checks/"*.json

  run notify_results

  assert_failure
  [ ! -f "$MOCK_BIN_DIR/np_calls.log" ]
}
