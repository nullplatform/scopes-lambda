#!/usr/bin/env bats
# Unit tests for the tracing hooks in lambda/utils/log

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	export LOG="$PROJECT_ROOT/lambda/utils/log"

	export NP_TRACE="1|trace-9|lambda-deployment-initial-42~update-function-code@0.0"
	export NP_API_KEY="test-key"
	export NP_TRACE_DIR="$BATS_TEST_TMPDIR/nptrace"
	export NP_TRACE_BASE_URL="http://127.0.0.1:1"
	export NP_TRACE_AUTH_URL="http://127.0.0.1:1"
	export NP_TRACE_FLUSH_TIMEOUT=1
	export NP_TRACE_MAX_RETRIES=0
}

teardown() {
	unset NP_TRACE NP_API_KEY NP_TRACE_DIR NP_TRACE_BASE_URL NP_TRACE_AUTH_URL
	unset NP_TRACE_FLUSH_TIMEOUT NP_TRACE_MAX_RETRIES
}

run_logged() {
	run "$BASH" -c "
		source '$LOG'
		$1
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
}

@test "the tracing SDK is bundled where the log util looks for it" {
	[ -f "$PROJECT_ROOT/vendor/catalog-tracing-sh/nptrace.sh" ]
}

@test "log error lands as a tracing.error facet on the current step" {
	run_logged 'log error "❌ Failed to update function code for fn"'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"run_id":"lambda-deployment-initial-42~update-function-code@0.0"'
	echo "$output" | grep -q '"tracing.error"'
	echo "$output" | grep -q '"message":"Failed to update function code for fn"'
}

@test "log error goes to stderr, other levels to stdout" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOG'; log info out; log error err 2>/dev/null"
	[ "$output" = "out" ]
	run "$BASH" -c "source '$LOG'; log info out >/dev/null; log error err 2>&1"
	[ "$output" = "err" ]
}

@test "without NP_TRACE, logging is plain logging" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOG'; log info hello; log error boom 2>&1; np_scope_failure OOM; np_scope_aws_failure x; echo rc=\$?"
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'hello\nboom\nrc=0')" ]
	[ ! -d "$NP_TRACE_DIR/spool" ]
}

@test "np_scope_failure labels the step with the cause, and the run with the reason" {
	run_logged 'np_scope_failure InsufficientRolePermissions'
	[ "$status" -eq 0 ]
	echo "$output" | grep 'update-function-code@0.0"' | grep -q '"failure.reason":"InsufficientRolePermissions"'
	echo "$output" | grep '"run_id":"lambda-deployment-initial-42"' | grep -q '"failure.reason":"InsufficientRolePermissions"'
}

@test "np_scope_aws_failure takes the AWS error code as the reason" {
	run_logged 'np_scope_aws_failure "An error occurred (ResourceConflictException) when calling the UpdateFunctionCode operation: An update is in progress"'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"failure.reason":"ResourceConflictException"'
}

@test "np_scope_aws_failure records nothing when the output carries no AWS error code" {
	run_logged 'np_scope_aws_failure "connection reset by peer"'
	[ "$status" -eq 0 ]
	! echo "$output" | grep -q 'failure.reason'
}

@test "a fatal exit mirrors the cause onto the run" {
	run "$BASH" -c "
		( source '$LOG'; log error '❌ the real reason'; exit 3 ) || true
		source '$LOG'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	echo "$output" | grep '"the real reason"' | grep -q 'update-function-code@0.0"'
	echo "$output" | grep '"the real reason"' | grep -q '"run_id":"lambda-deployment-initial-42"'
}

@test "sourcing the util twice initialises tracing once" {
	run_logged 'source "$LOG"; log error "once"'
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | grep -c '"message":"once"')" -eq 1 ]
}

@test "every action workflow loads the log util first and keeps plumbing out of the trace" {
	run python3 - "$PROJECT_ROOT/lambda" <<'PY'
import glob, sys, yaml
plumbing = {"assume_role", "build_context", "build_tofu_context", "build_destroy_context",
            "setup_provider", "setup_iam", "setup_compute", "compose_modules", "load_functions"}
for path in glob.glob(sys.argv[1] + "/*/workflows/*.yaml"):
    wf = yaml.safe_load(open(path))
    if "deployment/workflows" not in path and "scope/workflows" not in path:
        continue
    assert wf.get("trace", {}).get("title"), path
    steps = wf["steps"]
    if "diagnose" not in path:
        first = steps[0]
        assert first["name"] == "load_logging" and first["file"] == "$SERVICE_PATH/utils/log", path
        assert first["trace"] is False, path
        assert wf["trace"]["job"]["name"].startswith("lambda-"), path
    for step in steps:
        if step["name"] in plumbing:
            assert step.get("trace") is False, (path, step["name"])
print("ok")
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *ok* ]]
}
