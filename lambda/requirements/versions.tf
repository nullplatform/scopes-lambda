terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Lambda requirements only read data.aws_caller_identity; no dependency on
      # the aws_region.region attribute that forces >= 6.0 in the k8s module.
      version = ">= 5.0"
    }
  }
}
