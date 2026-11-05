################################################################################
# aws-lambda scope — installation, one AWS account
#
# The cloud side of the installation (what specs/requirements is today): the
# role the worker assumes, the scopes' state bucket and the repository the
# placeholder image lives in. One instance per account, whatever the number
# of environments the account serves: those are environment/ instances that
# take this module's outputs. Ownership rules:
#   - what is created here is owned, and destroy removes it;
#   - what the caller names is reused and left alone.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  installation_suffix = substr(replace(var.installation.id, "-", ""), 0, 8)

  role_arn     = coalesce(var.role_arn, try(aws_iam_role.lambda[0].arn, null))
  state_bucket = coalesce(var.state_bucket, try(aws_s3_bucket.state[0].bucket, null))

  create_role       = var.role_arn == null
  create_bucket     = var.state_bucket == null
  create_repository = var.placeholder_image_uri == null && var.placeholder_repository_url == null

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Account      = var.name
  }
}

# ── The role the worker assumes ──

resource "aws_iam_role" "lambda" {
  count = local.create_role ? 1 : 0

  name        = "nullplatform-${var.installation.package_slug}-${local.installation_suffix}-${var.name}"
  description = "Permissions role assumed by the nullplatform agent for the ${var.installation.package_slug} package (installation ${var.installation.id}, account ${var.name})"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.agent_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda" {
  count  = local.create_role ? 1 : 0
  name   = "lambda"
  role   = aws_iam_role.lambda[0].name
  policy = file("${path.module}/policies/lambda.json")
}

resource "aws_iam_role_policy" "lambda_iam" {
  count  = local.create_role ? 1 : 0
  name   = "lambda-iam"
  role   = aws_iam_role.lambda[0].name
  policy = file("${path.module}/policies/lambda-iam.json")
}

resource "aws_iam_role_policy" "lambda_networking" {
  count  = local.create_role ? 1 : 0
  name   = "lambda-networking"
  role   = aws_iam_role.lambda[0].name
  policy = file("${path.module}/policies/lambda-networking.json")
}

# The storage policy names the state bucket, so a given one is covered too.
resource "aws_iam_role_policy" "lambda_storage" {
  count = local.create_role ? 1 : 0
  name  = "lambda-storage"
  role  = aws_iam_role.lambda[0].name
  policy = templatefile("${path.module}/policies/lambda-storage.json.tftpl", {
    state_bucket       = local.state_bucket
    assets_bucket_name = var.assets_bucket_name
  })
}

# ── Per-scope OpenTofu state ──
# Named under the prefix the storage policy covers; the account id and name
# go in as a hash so the name stays under S3's 63 characters whatever the
# account is called (the tags carry both in clear).
resource "aws_s3_bucket" "state" {
  count = local.create_bucket ? 1 : 0

  bucket = "nullplatform-lambda-tfstate-${local.installation_suffix}-${substr(sha1("${data.aws_caller_identity.current.account_id}-${var.name}"), 0, 10)}"

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "state" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.state[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count                   = local.create_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.state[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── The private repository Lambda pulls the placeholder from ──
# One per account, under the name scope/placeholder/publish pushes to; that
# is why it lives here and not per environment, where two environments in
# one account would collide on it. The image itself is published by that
# script (docker buildx) and reported as missing until then.
resource "aws_ecr_repository" "placeholder" {
  count = local.create_repository ? 1 : 0

  name                 = "aws-lambda/nullplatform-lambda-placeholder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = local.tags
}
