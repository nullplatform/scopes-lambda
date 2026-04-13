# IAM role propagation delay
#
# AWS IAM changes replicate globally but not instantly. When a new role is
# created and immediately used to create a Lambda function, Lambda may return
# "The role defined for the function cannot be assumed" during the replication
# window (typically 5-15 seconds).
#
# This resource introduces a one-time sleep that fires only when the IAM role
# is first created (create_duration does not re-trigger on subsequent applies).
# When iam_create_role = false (role already exists), count = 0 and no sleep occurs.

resource "time_sleep" "iam_propagation" {
  count = var.iam_create_role ? 1 : 0

  create_duration = var.iam_propagation_duration

  depends_on = [
    aws_iam_role.lambda,
    aws_iam_role_policy_attachment.managed,
    aws_iam_role_policy.custom,
    aws_iam_role_policy.ecr,
    aws_iam_role_policy.secrets_manager_scope,
  ]
}
