mock_provider "aws" {}

variables {
  dns_hosted_zone_id     = "Z1234567890ABC"
  dns_domain             = "example.com"
  dns_subdomain          = "api"
  dns_full_domain        = "api.example.com"
  dns_resource_tags_json = {}
}

# --- API Gateway mode (alias record) ---

run "creates_alias_record_for_api_gateway" {
  variables {
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = length(aws_route53_record.api_gateway) == 1
    error_message = "API Gateway alias record should be created"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].name == "api.example.com"
    error_message = "Record name should be the full domain"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].type == "A"
    error_message = "Record type should be A for alias"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].zone_id == "Z1234567890ABC"
    error_message = "Zone ID should match"
  }
}

run "configures_alias_target_for_api_gateway" {
  variables {
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = length(aws_route53_record.api_gateway[0].alias) == 1
    error_message = "Alias block should be present"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].alias[0].name == "d-abc123.execute-api.us-east-1.amazonaws.com"
    error_message = "Alias target should be API Gateway domain"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].alias[0].zone_id == "Z1UJRXOUMOOFQ8"
    error_message = "Alias zone ID should be API Gateway regional zone"
  }

  assert {
    condition     = aws_route53_record.api_gateway[0].alias[0].evaluate_target_health == false
    error_message = "Should not evaluate target health"
  }
}

run "skips_alb_record_when_api_gateway_active" {
  variables {
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = length(aws_route53_record.alb) == 0
    error_message = "ALB record should not be created when API Gateway is active"
  }
}

# --- ALB mode (CNAME record) ---

run "creates_cname_record_for_alb" {
  variables {
    test_api_gateway_target_domain  = ""
    test_api_gateway_target_zone_id = ""
    test_alb_host_header            = "api.example.com"
  }
  command = plan

  assert {
    condition     = length(aws_route53_record.alb) == 1
    error_message = "ALB CNAME record should be created"
  }

  assert {
    condition     = aws_route53_record.alb[0].name == "api.example.com"
    error_message = "Record name should be the full domain"
  }

  assert {
    condition     = aws_route53_record.alb[0].type == "CNAME"
    error_message = "Record type should be CNAME for ALB"
  }

  assert {
    condition     = aws_route53_record.alb[0].ttl == 300
    error_message = "TTL should be 300"
  }
}

run "skips_api_gateway_record_when_alb_active" {
  variables {
    test_api_gateway_target_domain  = ""
    test_api_gateway_target_zone_id = ""
    test_alb_host_header            = "api.example.com"
  }
  command = plan

  assert {
    condition     = length(aws_route53_record.api_gateway) == 0
    error_message = "API Gateway record should not be created when ALB is active"
  }
}

# --- Common tests ---

run "uses_correct_hosted_zone" {
  variables {
    dns_hosted_zone_id              = "ZABCDEFGHIJKL"
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = aws_route53_record.api_gateway[0].zone_id == "ZABCDEFGHIJKL"
    error_message = "Record should be in the correct hosted zone"
  }
}

run "handles_subdomain_record" {
  variables {
    dns_full_domain                 = "api.prod.example.com"
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = aws_route53_record.api_gateway[0].name == "api.prod.example.com"
    error_message = "Record name should handle deep subdomains"
  }
}

run "handles_apex_domain_record" {
  variables {
    dns_full_domain                 = "example.com"
    test_api_gateway_target_domain  = "d-abc123.execute-api.us-east-1.amazonaws.com"
    test_api_gateway_target_zone_id = "Z1UJRXOUMOOFQ8"
  }
  command = plan

  assert {
    condition     = aws_route53_record.api_gateway[0].name == "example.com"
    error_message = "Record name should handle apex domain"
  }
}
