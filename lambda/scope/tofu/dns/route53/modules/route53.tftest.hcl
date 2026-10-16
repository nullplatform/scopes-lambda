mock_provider "aws" {}

variables {
  dns_hosted_zone_id = "Z1234567890ABC"
  dns_full_domain    = "api.example.com"
  dns_alb_dns_name   = "internal-my-alb-123456.us-east-1.elb.amazonaws.com"
  dns_alb_zone_id    = "Z35SXDOTRQ7X7K"
}

run "creates_alias_record_for_alb" {
  command = plan

  assert {
    condition     = aws_route53_record.alb.name == "api.example.com"
    error_message = "Record name should be the full domain"
  }

  assert {
    condition     = aws_route53_record.alb.type == "A"
    error_message = "Record type should be A for alias"
  }

  assert {
    condition     = aws_route53_record.alb.zone_id == "Z1234567890ABC"
    error_message = "Zone ID should match"
  }
}

run "aliases_the_selected_alb" {
  command = plan

  assert {
    condition     = aws_route53_record.alb.alias[0].name == "internal-my-alb-123456.us-east-1.elb.amazonaws.com"
    error_message = "Alias target should be the ALB DNS name"
  }

  assert {
    condition     = aws_route53_record.alb.alias[0].zone_id == "Z35SXDOTRQ7X7K"
    error_message = "Alias zone ID should be the ALB canonical zone"
  }

  assert {
    condition     = aws_route53_record.alb.alias[0].evaluate_target_health == false
    error_message = "Should not evaluate target health"
  }
}

run "follows_a_move_to_another_alb" {
  variables {
    dns_alb_dns_name = "internal-other-alb-654321.us-east-1.elb.amazonaws.com"
    dns_alb_zone_id  = "Z35SXDOTRQ7X7K"
  }
  command = plan

  assert {
    condition     = aws_route53_record.alb.alias[0].name == "internal-other-alb-654321.us-east-1.elb.amazonaws.com"
    error_message = "Alias should follow the ALB the scope was assigned to"
  }
}
