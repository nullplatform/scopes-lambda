output "role_arn" {
  description = "The role the worker assumes in this account, created here or given. environment/ registers it in each environment's IAM provider."
  value       = local.role_arn
}

output "state_bucket" {
  description = "The scopes' OpenTofu state bucket, created here or given. environment/ writes it in each environment's scope-configuration."
  value       = local.state_bucket
}

output "state_bucket_region" {
  description = "Region of the state bucket: the account's, so environment/ needs no AWS provider."
  value       = data.aws_region.current.region
}

output "placeholder_image_uri" {
  description = "The placeholder image, given or null while it is still to be published."
  value       = var.placeholder_image_uri
}

output "placeholder_repository_url" {
  description = "The placeholder repository, created here or given."
  value       = coalesce(var.placeholder_repository_url, try(aws_ecr_repository.placeholder[0].repository_url, null), try(split(":", var.placeholder_image_uri)[0], null))
}

output "resources" {
  description = "What this module touched, with who owns it: owned (created here, removed on destroy), provided (given, never removed)."
  value = concat(
    [for role in aws_iam_role.lambda : { type = "aws_iam_role", id = role.arn, account = var.name, ownership = "owned" }],
    var.role_arn != null ? [{ type = "aws_iam_role", id = var.role_arn, account = var.name, ownership = "provided" }] : [],
    [for bucket in aws_s3_bucket.state : { type = "aws_s3_bucket", id = bucket.bucket, account = var.name, ownership = "owned" }],
    var.state_bucket != null ? [{ type = "aws_s3_bucket", id = var.state_bucket, account = var.name, ownership = "provided" }] : [],
    [for repo in aws_ecr_repository.placeholder : { type = "aws_ecr_repository", id = repo.repository_url, account = var.name, ownership = "owned" }],
    var.placeholder_repository_url != null ? [{ type = "aws_ecr_repository", id = var.placeholder_repository_url, account = var.name, ownership = "provided" }] : [],
    var.placeholder_image_uri != null ? [{ type = "placeholder_image", id = var.placeholder_image_uri, account = var.name, ownership = "provided" }] : [],
    var.alb_listener_arn != null ? [{ type = "alb_listener", id = var.alb_listener_arn, account = var.name, ownership = "provided" }] : [],
  )
}

output "missing" {
  description = "Requirements that could not be satisfied here, with what to do."
  value = concat(
    var.placeholder_image_uri == null ? [{ need = "placeholder_image", account = var.name, hint = "publish it with scope/placeholder/publish (PLACEHOLDER_IMAGE_REPO=<repository url>), then pass placeholder_image_uri" }] : [],
    var.alb_listener_arn == null ? [{ need = "alb_listener", account = var.name, hint = "optional: scopes get no HTTP endpoint through an ALB; pass alb_listener_arn" }] : [],
  )
}
