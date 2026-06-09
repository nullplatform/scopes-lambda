terraform {
  backend "s3" {
    key = "lambda/specs/tofu/terraform.tfstate"
  }
}
