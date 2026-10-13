#!/bin/bash
# ELBv2 mock keyed by ARN, for scripts that compare several ALBs. aws_cli_mock.bash keys
# by subcommand only, so it cannot give two load balancers different rule counts.
#
#   setup_alb_mock
#   mock_alb "$LB_A" "$LISTENER_A" 40          # an ALB whose listener holds 40 rules
#   mock_scope_rule "$LISTENER_A" "api.example.com" 140
#   mock_cloudwatch_failure

setup_alb_mock() {
  : "${MOCK_BIN_DIR:?setup_alb_mock requires MOCK_BIN_DIR}"
  ALB_MOCK_DIR="$MOCK_BIN_DIR/alb"
  mkdir -p "$ALB_MOCK_DIR"
  : > "$MOCK_BIN_DIR/aws_calls"

  cat > "$MOCK_BIN_DIR/aws" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
printf '%s\n' "$*" >> "$MOCK_DIR/aws_calls"

arg_after() {
  local flag="$1"; shift
  while [ $# -gt 0 ]; do
    [ "$1" = "$flag" ] && { echo "$2"; return; }
    shift
  done
}
key() { echo "$1" | cksum | cut -d' ' -f1; }
serve() {
  if [ -f "$1" ]; then cat "$1"; exit 0; fi
  echo "${2:-mock: no fixture}" >&2
  exit 254
}

case "$1 $2" in
  "elbv2 describe-listeners")
    listener=$(arg_after --listener-arns "$@")
    if [ -n "$listener" ]; then
      serve "$MOCK_DIR/alb/listener_$(key "$listener")" \
        "An error occurred (ListenerNotFound) when calling the DescribeListeners operation"
    fi
    serve "$MOCK_DIR/alb/lb_listeners_$(key "$(arg_after --load-balancer-arn "$@")")"
    ;;
  "elbv2 describe-rules")
    serve "$MOCK_DIR/alb/rules_$(key "$(arg_after --listener-arn "$@")")"
    ;;
  "elbv2 describe-load-balancers")
    serve "$MOCK_DIR/alb/lb_$(key "$(arg_after --load-balancer-arns "$@")")"
    ;;
  "s3api head-object")
    [ -f "$MOCK_DIR/alb/s3_head_error" ] && { cat "$MOCK_DIR/alb/s3_head_error" >&2; exit 254; }
    exit 0
    ;;
  "cloudwatch put-metric-data")
    [ -f "$MOCK_DIR/alb/cloudwatch_fails" ] && { echo "AccessDenied" >&2; exit 254; }
    exit 0
    ;;
esac
exit 0
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/aws"
}

_alb_key() { echo "$1" | cksum | cut -d' ' -f1; }

# mock_alb <lb_arn> <listener_arn> <rule_count>: a listener holding <rule_count> host rules
# with priorities 1..N, plus the default rule. Repeat with the same lb to add listeners.
mock_alb() {
  local lb="$1" listener="$2" count="$3" lb_file
  jq -nc --arg l "$listener" --arg lb "$lb" '{Listeners: [{ListenerArn: $l, LoadBalancerArn: $lb}]}' \
    > "$ALB_MOCK_DIR/listener_$(_alb_key "$listener")"
  lb_file="$ALB_MOCK_DIR/lb_listeners_$(_alb_key "$lb")"
  [ -f "$lb_file" ] || echo '{"Listeners":[]}' > "$lb_file"
  jq -c --arg l "$listener" --arg lb "$lb" \
    '.Listeners = ([.Listeners[] | select(.ListenerArn != $l)] + [{ListenerArn: $l, LoadBalancerArn: $lb}])' \
    "$lb_file" > "$lb_file.tmp" && mv "$lb_file.tmp" "$lb_file"
  jq -nc --argjson n "$count" '{Rules: ([range(1; $n + 1) | {
      Priority: (. | tostring), IsDefault: false,
      Conditions: [{Field: "host-header", HostHeaderConfig: {Values: ["other-\(.).example.com"]}}]}]
    + [{Priority: "default", IsDefault: true, Conditions: []}])}' \
    > "$ALB_MOCK_DIR/rules_$(_alb_key "$listener")"
  jq -nc --arg lb "$lb" '{LoadBalancers: [{LoadBalancerArn: $lb, DNSName: "dns-\($lb | split("/")[2]).elb.amazonaws.com", CanonicalHostedZoneId: "ZALB"}]}' \
    > "$ALB_MOCK_DIR/lb_$(_alb_key "$lb")"
}

# mock_scope_rule <listener_arn> <host> <priority>: add the scope's own rule to a listener.
mock_scope_rule() {
  local file
  file="$ALB_MOCK_DIR/rules_$(_alb_key "$1")"
  jq -c --arg h "$2" --arg p "$3" '.Rules += [{Priority: $p, IsDefault: false,
    Conditions: [{Field: "host-header", HostHeaderConfig: {Values: [$h]}}]}]' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# mock_s3_head_error '<stderr>': make s3api head-object fail with that message.
mock_s3_head_error() {
  printf '%s' "$1" > "$ALB_MOCK_DIR/s3_head_error"
}

mock_cloudwatch_failure() {
  touch "$ALB_MOCK_DIR/cloudwatch_fails"
}

assert_aws_call_contains() {
  if ! grep -qF -- "$1" "$MOCK_BIN_DIR/aws_calls"; then
    echo "Expected an aws call containing: $1"
    sed 's/^/  - aws /' "$MOCK_BIN_DIR/aws_calls"
    return 1
  fi
}

# create_nrn_mock '<json for np nrn read>': answers nrn read and records every np call.
create_nrn_mock() {
  : > "$MOCK_BIN_DIR/np_calls"
  printf '%s' "${1:-{\}}" > "$MOCK_BIN_DIR/np_nrn"
  cat > "$MOCK_BIN_DIR/np" << 'MOCK_SCRIPT'
#!/bin/bash
MOCK_DIR="$(dirname "$0")"
printf '%s\n' "$*" >> "$MOCK_DIR/np_calls"
[ -f "$MOCK_DIR/np_fails" ] && { echo "np failed" >&2; exit 1; }
if [ "$1 $2" = "nrn read" ]; then cat "$MOCK_DIR/np_nrn"; else echo '{}'; fi
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}
