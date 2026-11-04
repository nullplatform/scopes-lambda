################################################################################
# aws-lambda scope — installation, one target (one AWS account)
#
# The cloud side of the installation for one account (what specs/requirements
# is today), plus what the runtime reads per environment: the IAM provider
# entry and the scope-configuration values. Ownership rules:
#   - what is created here is owned, and destroy removes it;
#   - what the caller names is reused: an IAM provider only gets this
#     package's entry; a scope-configuration, a bucket, an image, a repository
#     are left alone.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  installation_suffix = substr(replace(var.installation.id, "-", ""), 0, 8)

  role_arn     = coalesce(var.role_arn, try(aws_iam_role.lambda[0].arn, null))
  state_bucket = coalesce(var.state_bucket, try(aws_s3_bucket.state[0].bucket, null))

  create_role         = var.role_arn == null
  create_bucket       = var.state_bucket == null
  create_repository   = var.placeholder_image_uri == null && var.placeholder_repository_url == null
  create_iam_provider = var.iam_provider_id == null
  write_entry         = var.iam_provider_id != null && !var.role_from_entry
  # A scope-configuration can be written only once the image is known.
  create_configuration = var.scope_configuration_id == null && var.placeholder_image_uri != null
}

# ── The role the worker assumes ──

resource "aws_iam_role" "lambda" {
  count = local.create_role ? 1 : 0

  name        = "nullplatform-${var.installation.package_slug}-${local.installation_suffix}-${var.name}"
  description = "Permissions role assumed by the nullplatform agent for the ${var.installation.package_slug} package (installation ${var.installation.id}, target ${var.name})"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.agent_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = var.name
  }
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
# Named under the prefix the storage policy covers; the account and the target
# go in as a hash so the name stays under S3's 63 characters whatever the
# target is called (the tags carry both in clear).
resource "aws_s3_bucket" "state" {
  count = local.create_bucket ? 1 : 0

  bucket = "nullplatform-lambda-tfstate-${local.installation_suffix}-${substr(sha1("${data.aws_caller_identity.current.account_id}-${var.name}"), 0, 10)}"

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = var.name
  }
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
# The image itself is published by scope/placeholder/publish (docker buildx)
# and reported as missing until then.
resource "aws_ecr_repository" "placeholder" {
  count = local.create_repository ? 1 : 0

  name                 = "aws-lambda/nullplatform-lambda-placeholder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = var.name
  }
}

# ── Where the runtime reads it: IAM provider and scope-configuration values ──

# A target with no IAM provider gets one, owned here, holding only this entry.
resource "nullplatform_provider_config" "iam" {
  count = local.create_iam_provider ? 1 : 0

  nrn        = var.installation.nrn
  type       = "aws-iam-configuration"
  dimensions = var.dimensions
  attributes = jsonencode({
    iam_role_arns = { arns = [{ selector = "lambda", arn = local.role_arn }] }
  })
}

# An existing IAM provider gets exactly one entry added, removed on destroy.
# Script until the API has an entry endpoint; a nullplatform_iam_role_entry
# resource would swap in here. Values reach the script through its
# environment, never interpolated into the shell line.
resource "terraform_data" "iam_role_entry" {
  count = local.write_entry ? 1 : 0

  triggers_replace = {
    provider_id = var.iam_provider_id
    selector    = "lambda"
    arn         = local.role_arn
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/iam_role_entry upsert \"$PROVIDER_ID\" \"$SELECTOR\" \"$ROLE_ARN\""
    environment = {
      PROVIDER_ID = self.triggers_replace.provider_id
      SELECTOR    = self.triggers_replace.selector
      ROLE_ARN    = self.triggers_replace.arn
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/iam_role_entry remove \"$PROVIDER_ID\" \"$SELECTOR\""
    environment = {
      PROVIDER_ID = self.triggers_replace.provider_id
      SELECTOR    = self.triggers_replace.selector
    }
  }
}

# The scope-configuration values the runtime reads by dimensions.
resource "nullplatform_provider_config" "scope_configuration" {
  count = local.create_configuration ? 1 : 0

  nrn        = var.installation.nrn
  type       = var.scope_configuration_slug
  dimensions = var.dimensions
  attributes = jsonencode({
    state      = { tofu_state_bucket = local.state_bucket, tofu_state_bucket_region = data.aws_region.current.region }
    deployment = { placeholder_image_uri = var.placeholder_image_uri }
  })
}
