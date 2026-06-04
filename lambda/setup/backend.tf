terraform {
  backend "s3" {
    key = "lambda/setup/terraform.tfstate"
  }
}
