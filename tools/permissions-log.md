# Permissions Log — Lambda Scope Least Privilege

Permissions discovered during sandbox iteration that need to be added to `custom-scope-role` in production.

| Date | Action(s) | SID | Resource |
|------|-----------|-----|----------|
| 2026-04-06 18:07 UTC | `lambda:GetFunctionCodeSigningConfig` | LambdaRead | `*` |
| 2026-04-06 18:22 UTC | `iam:ListInstanceProfilesForRole` | IamRoleReadOnly | `*` |
