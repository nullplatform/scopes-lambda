#!/bin/bash
# ELBv2 mock keyed by ARN, for scripts that compare several ALBs. aws_cli_mock.bash keys
# by subcommand only, so it cannot give two load balancers different rule counts.
#
#   setup_alb_mock
#   mock_alb "$LB_A" "$LISTENER_A" 40          # an ALB whose listener holds 40 rules
#   mock_scope_rule "$LISTENER_A" "api.example.com" 140
#   mock_cloudwatch_failure
#   mock_providers '<json for np provider list>'

# What describe-listeners returns besides the ARNs: an HTTPS listener with a 404 default.
ALB_MOCK_LISTENER_DEFAULTS='{"Port":443,"Protocol":"HTTPS","SslPolicy":"ELBSecurityPolicy-2016-08","Certificates":[{"CertificateArn":"arn:aws:acm:us-east-1:111122223333:certificate/wild"}],"DefaultActions":[{"Type":"fixed-response","FixedResponseConfig":{"StatusCode":"404","ContentType":"text/plain"}}]}'

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
  "elbv2 describe-target-groups")
    serve "$MOCK_DIR/alb/tgs_$(key "$(arg_after --load-balancer-arn "$@")")"
    ;;
  "elbv2 describe-load-balancers")
    name=$(arg_after --names "$@")
    if [ -n "$name" ]; then
      serve "$MOCK_DIR/alb/lb_name_$(key "$name")" \
        "An error occurred (LoadBalancerNotFound) when calling the DescribeLoadBalancers operation"
    fi
    serve "$MOCK_DIR/alb/lb_$(key "$(arg_after --load-balancer-arns "$@")")"
    ;;
  "elbv2 describe-tags")
    f="$MOCK_DIR/alb/tags_$(key "$(arg_after --resource-arns "$@")")"
    if [ -f "$f" ]; then cat "$f"; else echo '{"TagDescriptions":[{"Tags":[]}]}'; fi
    ;;
  "elbv2 describe-load-balancer-attributes")
    echo '{"Attributes":[{"Key":"idle_timeout.timeout_seconds","Value":"120"}]}'
    ;;
  "elbv2 describe-listener-certificates")
    f="$MOCK_DIR/alb/certs_$(key "$(arg_after --listener-arn "$@")")"
    if [ -f "$f" ]; then cat "$f"; else echo '{"Certificates":[]}'; fi
    ;;
  "elbv2 create-load-balancer")
    [ -f "$MOCK_DIR/alb/create_lb_fails" ] && { echo "TooManyLoadBalancers" >&2; exit 254; }
    name=$(arg_after --cli-input-json "$@" | jq -r '.Name')
    lb="arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/$name/new"
    jq -nc --arg lb "$lb" --arg n "$name" '{LoadBalancers: [{LoadBalancerArn: $lb, LoadBalancerName: $n,
      DNSName: "dns-\($n).elb.amazonaws.com", CanonicalHostedZoneId: "ZALB"}]}' | tee "$MOCK_DIR/alb/lb_$(key "$lb")"
    echo '{"Listeners":[]}' > "$MOCK_DIR/alb/lb_listeners_$(key "$lb")"
    ;;
  "elbv2 create-listener")
    input=$(arg_after --cli-input-json "$@")
    lb=$(echo "$input" | jq -r '.LoadBalancerArn')
    listener="${lb/:loadbalancer\//:listener/}/l$(echo "$input" | jq -r '.Port')"
    listener_json=$(echo "$input" | jq -c --arg l "$listener" '. + {ListenerArn: $l}')
    echo "{\"Listeners\":[$listener_json]}" | tee "$MOCK_DIR/alb/listener_$(key "$listener")"
    jq -c --argjson l "$listener_json" '.Listeners += [$l]' "$MOCK_DIR/alb/lb_listeners_$(key "$lb")" \
      > "$MOCK_DIR/alb/tmp" && mv "$MOCK_DIR/alb/tmp" "$MOCK_DIR/alb/lb_listeners_$(key "$lb")"
    echo '{"Rules":[{"Priority":"default","IsDefault":true,"Conditions":[]}]}' > "$MOCK_DIR/alb/rules_$(key "$listener")"
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
# with priorities 1..N, plus the default rule, and as many target groups.
# Repeat with the same lb to add listeners.
mock_alb() {
  local lb="$1" listener="$2" count="$3" lb_file
  jq -nc --arg l "$listener" --arg lb "$lb" '{Listeners: [{ListenerArn: $l, LoadBalancerArn: $lb}]}' \
    | jq -c --argjson d "$ALB_MOCK_LISTENER_DEFAULTS" '.Listeners[0] += $d' > "$ALB_MOCK_DIR/listener_$(_alb_key "$listener")"
  lb_file="$ALB_MOCK_DIR/lb_listeners_$(_alb_key "$lb")"
  [ -f "$lb_file" ] || echo '{"Listeners":[]}' > "$lb_file"
  jq -c --arg l "$listener" --arg lb "$lb" \
    --argjson d "$ALB_MOCK_LISTENER_DEFAULTS" \
    '.Listeners = ([.Listeners[] | select(.ListenerArn != $l)] + [{ListenerArn: $l, LoadBalancerArn: $lb} + $d])' \
    "$lb_file" > "$lb_file.tmp" && mv "$lb_file.tmp" "$lb_file"
  jq -nc --argjson n "$count" '{Rules: ([range(1; $n + 1) | {
      Priority: (. | tostring), IsDefault: false,
      Conditions: [{Field: "host-header", HostHeaderConfig: {Values: ["other-\(.).example.com"]}}]}]
    + [{Priority: "default", IsDefault: true, Conditions: []}])}' \
    > "$ALB_MOCK_DIR/rules_$(_alb_key "$listener")"
  jq -nc --argjson n "$count" '{TargetGroups: [range(0; $n) | {}]}' > "$ALB_MOCK_DIR/tgs_$(_alb_key "$lb")"
  jq -nc --arg lb "$lb" '{LoadBalancers: [{LoadBalancerArn: $lb, DNSName: "dns-\($lb | split("/")[2]).elb.amazonaws.com", CanonicalHostedZoneId: "ZALB",
      Scheme: "internal", IpAddressType: "ipv4", SecurityGroups: ["sg-1"],
      AvailabilityZones: [{SubnetId: "subnet-1"}, {SubnetId: "subnet-2"}]}]}' \
    > "$ALB_MOCK_DIR/lb_$(_alb_key "$lb")"
}

# mock_scope_rule <listener_arn> <host> <priority> [target_group_name]: add the scope's own rule.
mock_scope_rule() {
  local file
  file="$ALB_MOCK_DIR/rules_$(_alb_key "$1")"
  jq -c --arg h "$2" --arg p "$3" --arg tg "${4:-tg-$3}" '.Rules += [{Priority: $p, IsDefault: false,
    Conditions: [{Field: "host-header", HostHeaderConfig: {Values: [$h]}}],
    Actions: [{Type: "forward", TargetGroupArn: "arn:aws:elasticloadbalancing:us-east-1:111122223333:targetgroup/\($tg)/abc"}]}]' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# mock_s3_head_error '<stderr>': make s3api head-object fail with that message.
mock_s3_head_error() {
  printf '%s' "$1" > "$ALB_MOCK_DIR/s3_head_error"
}

mock_create_lb_failure() {
  touch "$ALB_MOCK_DIR/create_lb_fails"
}

# mock_existing_alb_name <name> <lb_arn> [autocreate tag value]: a load balancer already using that name.
mock_existing_alb_name() {
  jq -nc --arg lb "$2" '{LoadBalancers: [{LoadBalancerArn: $lb}]}' > "$ALB_MOCK_DIR/lb_name_$(_alb_key "$1")"
  [ -n "${3:-}" ] && jq -nc --arg v "$3" '{TagDescriptions: [{Tags: [{Key: "nullplatform:lambda-autocreated", Value: $v}]}]}' \
    > "$ALB_MOCK_DIR/tags_$(_alb_key "$2")"
  return 0
}

# mock_alb_tags <lb_arn> '<tags json array>'
mock_alb_tags() {
  jq -nc --argjson t "$2" '{TagDescriptions: [{Tags: $t}]}' > "$ALB_MOCK_DIR/tags_$(_alb_key "$1")"
}

# mock_listener_certificates <listener_arn> <cert_arn>...: extra (non-default) certificates.
mock_listener_certificates() {
  local listener="$1"; shift
  printf '%s\n' "$@" | jq -Rnc '{Certificates: [inputs | {CertificateArn: ., IsDefault: false}]}' \
    > "$ALB_MOCK_DIR/certs_$(_alb_key "$listener")"
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
case "$1 $2" in
  "nrn read") cat "$MOCK_DIR/np_nrn" ;;
  "provider list") cat "$MOCK_DIR/np_providers" 2>/dev/null || echo '{"results":[]}' ;;
  *) echo '{}' ;;
esac
MOCK_SCRIPT
  chmod +x "$MOCK_BIN_DIR/np"
}

# mock_providers '<json for np provider list>'
mock_providers() {
  printf '%s' "$1" > "$MOCK_BIN_DIR/np_providers"
}
