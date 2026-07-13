###############################################################################
# Optional public ALB for AWS Lambda HTTP exposure.
#
# Off by default (var.install_alb = false) so stacks that only need the Lambda
# IAM permissions role are unaffected. When enabled, this creates a dedicated
# public ALB + HTTPS(443)/HTTP(80->redirect) listeners + security group. The
# Lambda scope workflow registers per-scope target groups and listener rules on
# this listener at runtime (host-header routing), reading the listener ARN from
# the aws-networking-configuration provider.
#
# Certificate: created here (wildcard, DNS-validated via var.public_zone_id)
# unless var.certificate_arn is supplied — pass an existing wildcard ARN to
# reuse the cert already used by static-files instead of minting a second one.
#
# Subnets: discovered by the `nullplatform/subnet-type=public` tag on var.vpc_id,
# or taken from var.public_subnet_ids when provided (clusters without the tag).
###############################################################################

locals {
  alb_create  = var.install_alb
  create_cert = var.install_alb && var.certificate_arn == ""

  alb_name = var.alb_name != "" ? var.alb_name : "np-${var.cluster_name}-lambda"

  alb_subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : (
    local.alb_create ? data.aws_subnets.public[0].ids : []
  )

  alb_certificate_arn = var.certificate_arn != "" ? var.certificate_arn : (
    local.create_cert ? aws_acm_certificate_validation.lambda_wildcard[0].certificate_arn : ""
  )

  alb_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "nullplatform-custom-scope-role"
    Module    = local.iam_module_name
    Purpose   = "lambda-public-alb"
  })
}

data "aws_subnets" "public" {
  count = local.alb_create && length(var.public_subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:nullplatform/subnet-type"
    values = ["public"]
  }
}

# --- Wildcard certificate (only when no certificate_arn is provided) ---------
resource "aws_acm_certificate" "lambda_wildcard" {
  count = local.create_cert ? 1 : 0

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = local.alb_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "lambda_wildcard_validation" {
  count = local.create_cert ? 1 : 0

  zone_id         = var.public_zone_id
  name            = tolist(aws_acm_certificate.lambda_wildcard[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.lambda_wildcard[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.lambda_wildcard[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "lambda_wildcard" {
  count = local.create_cert ? 1 : 0

  certificate_arn         = aws_acm_certificate.lambda_wildcard[0].arn
  validation_record_fqdns = [aws_route53_record.lambda_wildcard_validation[0].fqdn]
}

# --- Security group ----------------------------------------------------------
resource "aws_security_group" "lambda_alb_public" {
  count = local.alb_create ? 1 : 0

  name        = "${local.alb_name}-alb-public"
  description = "Allow HTTPS + HTTP (redirected) from the internet to the public Lambda ALB."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirected to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress (ALB to Lambda invoke)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.alb_tags
}

# --- ALB + listeners ---------------------------------------------------------
resource "aws_lb" "lambda_public" {
  count = local.alb_create ? 1 : 0

  name                       = local.alb_name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.lambda_alb_public[0].id]
  subnets                    = local.alb_subnet_ids
  enable_deletion_protection = false

  tags = local.alb_tags
}

# HTTPS:443 — TLS terminated with the wildcard cert. Default action is a fixed
# 404; per-scope host-header rules are added at runtime by the Lambda workflow.
resource "aws_lb_listener" "lambda_public_https" {
  count = local.alb_create ? 1 : 0

  load_balancer_arn = aws_lb.lambda_public[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.alb_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 - no scope matches this host"
      status_code  = "404"
    }
  }

  tags = local.alb_tags
}

# HTTP:80 -> redirect to HTTPS:443.
resource "aws_lb_listener" "lambda_public_http" {
  count = local.alb_create ? 1 : 0

  load_balancer_arn = aws_lb.lambda_public[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.alb_tags
}
