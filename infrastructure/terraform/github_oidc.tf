# github_oidc.tf
# Lets GitHub Actions authenticate to AWS with no stored credentials.
# GitHub issues a short-lived signed token per workflow run; AWS verifies
# it really came from GitHub AND that it's from this exact repo, then
# hands back temporary AWS credentials that expire within the hour.
#
# Project 101 equivalent: none — Project 101's CI (flake8/pytest) never
# touched AWS. This is new territory: CI/CD that can actually change
# real infrastructure, which is why the trust condition below matters.

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI/CD role, as \"owner/repo\""
  type        = string
  default     = "Thierry0326/Project102_AWS_Pipeline"
}

# ----------------------------------------------
# TRUST ANCHOR
# Fetches GitHub's current OIDC TLS cert thumbprint live instead of
# hardcoding one. GitHub rotated this cert once already (2023) - a
# hardcoded thumbprint would silently break CI/CD whenever it happens
# again, with no obvious error pointing at the cause.
# ----------------------------------------------
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "${var.project_name}-github-oidc"
    Description = "Trust anchor so GitHub Actions tokens are accepted by AWS STS"
  }
}

# ----------------------------------------------
# ROLE — what GitHub Actions becomes once trusted
# The "sub" condition is the important line: it restricts which
# workflows can assume this role to exactly this repo. Without it, ANY
# GitHub Actions workflow on ANY repo (yours or anyone else's) could
# assume this role and touch your AWS account.
# ----------------------------------------------
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-github-actions-role"
    Description = "Assumed by GitHub Actions via OIDC to run terraform plan/apply"
  }
}

# ----------------------------------------------
# PERMISSIONS — scoped to project102-* resources, not AdministratorAccess
# Grouped by service since each AWS service supports resource-level
# restriction differently (some by ARN name pattern, some only by "*").
# This is a solid first pass, not a guarantee of zero AccessDenied
# errors — if terraform plan/apply in CI hits a missing permission,
# that's a normal part of getting this right, same as every other bug
# in this project got found by hitting the actual error.
# ----------------------------------------------
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "${var.project_name}-github-actions-terraform"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBackend"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::project102-s3-terraform-state",
          "arn:aws:s3:::project102-s3-terraform-state/*"
        ]
      },
      {
        # s3:Get* instead of enumerating individual read actions - the AWS
        # provider's aws_s3_bucket resource calls a long, not-fully-
        # documented batch of Get* APIs on every refresh (ACL, policy,
        # CORS, website, logging, replication, object-lock config, and
        # more), independent of which of those we actually declared a
        # resource for. Enumerating them one at a time cost 2 CI round
        # trips (GetBucketPolicy, then GetBucketAcl) before this - s3:Get*
        # is a safe wildcard specifically because every action in that
        # namespace is read-only, unlike s3:* (Trivy AWS-0345), which
        # still needs the explicit list below for mutation actions.
        Sid    = "S3DataBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:Get*",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectTagging",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::project102-*",
          "arn:aws:s3:::project102-*/*"
        ]
      },
      {
        # EC2/VPC create+describe actions mostly don't support ARN-level
        # resource restriction - that's a normal AWS limitation for this
        # service, not something left loose by mistake.
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:*Vpc*",
          "ec2:*Subnet*",
          "ec2:*SecurityGroup*",
          "ec2:*Tags",
          "ec2:DescribeAvailabilityZones",
          # Needed to resolve the S3 Gateway Endpoint's service name to a
          # prefix list ID - read-only AWS-wide lookup, no resource scoping.
          "ec2:DescribePrefixLists"
        ]
        Resource = "*"
      },
      {
        Sid    = "GlueETL"
        Effect = "Allow"
        Action = "glue:*"
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.project_name}*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}*/*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${var.project_name}-*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:crawler/${var.project_name}-*"
        ]
      },
      {
        Sid    = "IAMForProject102Roles"
        Effect = "Allow"
        Action = ["iam:*Role*", "iam:*Policy*"]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
          "arn:aws:iam::aws:policy/*"
        ]
      },
      {
        Sid      = "PassProject102Roles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*"
      },
      {
        # Covers this file's own OIDC provider + role, so future edits
        # to github_oidc.tf can be applied by CI itself. First-time
        # creation (right now) still has to happen manually, though -
        # the role can't create itself before it exists.
        Sid    = "SelfManageOIDC"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNS"
        Effect   = "Allow"
        Action   = "sns:*"
        Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-*"
      },
      {
        Sid      = "StepFunctions"
        Effect   = "Allow"
        Action   = "states:*"
        Resource = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-*"
      },
      {
        # ValidateStateMachineDefinition runs before the resource has a
        # name/ARN of its own (that's the whole point - it's checking the
        # definition is well-formed prior to creation), so AWS always
        # calls it against a generic stateMachine:* pattern regardless of
        # what you're about to name the real resource. Can't be scoped
        # to project102-* the way the statement above is.
        Sid      = "ValidateStateMachineDefinition"
        Effect   = "Allow"
        Action   = "states:ValidateStateMachineDefinition"
        Resource = "*"
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = "secretsmanager:*"
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"
      },
      {
        # For eventbridge.tf - currently disabled, harmless to grant now
        Sid      = "EventBridge"
        Effect   = "Allow"
        Action   = "events:*"
        Resource = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${var.project_name}-*"
      },
      {
        Sid      = "AccountDiscovery"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}
