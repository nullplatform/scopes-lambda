terraform {
  required_providers {
    nullplatform = {
      source  = "nullplatform/nullplatform"
      version = ">= 0.0.90, < 0.1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "nullplatform" {
  api_key = var.np_api_key
}

provider "aws" {
  region = var.aws_region
}
