# Project 102 — Troubleshooting Guide

This document records all issues encountered during setup and how they
were resolved. Updated after every phase. Use this as a reference if
you encounter similar problems.

---

## Table of Contents

1. [Terraform App Cannot Run on PC](#1-terraform-app-cannot-run-on-pc)
2. [Terraform Init Network Timeout](#2-terraform-init-network-timeout)
3. [Deprecated dynamodb_table Parameter](#3-deprecated-dynamodb_table-parameter)
4. [variable.tf Named Incorrectly](#4-variabletf-named-incorrectly)
5. [gitattributes Invalid Attribute Warning](#5-gitattributes-invalid-attribute-warning)
6. [LF Will Be Replaced by CRLF Warning](#6-lf-will-be-replaced-by-crlf-warning)
7. [Invalid Resource Type aws_s3_lifecycle_configuration](#7-invalid-resource-type-aws_s3_lifecycle_configuration)
8. [Lifecycle Rule Missing Filter Block](#8-lifecycle-rule-missing-filter-block)
9. [InvalidTag — Em Dash in Tag Values](#9-invalidtag--em-dash-in-tag-values)
10. [InvalidTag — Box Drawing Characters in Comments](#10-invalidtag--box-drawing-characters-in-comments)
11. [Terraform Init Run from Wrong Directory](#11-terraform-init-run-from-wrong-directory)

---

## Phase 0 — Foundation

---

### 1. Terraform App Cannot Run on PC

**Phase:** 0 — Terraform Installation

**Symptom**
```
This app can't run on your PC.
To find a version for your PC, check with the software publisher.
```

**Cause**
Downloaded the wrong architecture version of the Terraform installer
from the website (32-bit or ARM instead of Windows AMD64).

**Fix**
Install via PowerShell instead of manual download:

```powershell
# Option A - winget (simplest)
winget install HashiCorp.Terraform

# Option B - manual PowerShell download (correct architecture)
Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_windows_amd64.zip" -OutFile "terraform.zip"
Expand-Archive -Path "terraform.zip" -DestinationPath "C:\terraform"
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\terraform", [EnvironmentVariableTarget]::Machine)
```

Open a new terminal after installation and verify:
```powershell
terraform --version
```

**Prevention**
Always use `winget` on Windows for CLI tool installation — it
automatically selects the correct architecture.

---

### 2. Terraform Init Network Timeout

**Phase:** 0 — Terraform Initialization

**Symptom**
```
Error: Failed to install provider
Error while installing hashicorp/aws v5.100.0:
releases.hashicorp.com: read tcp ...: wsarecv: A connection attempt
failed because the connected party did not properly respond after a
period of time
```

**Cause**
Unstable internet connection dropped during the ~80MB AWS provider
download from `releases.hashicorp.com`.

**Fix**
Simply retry — Terraform retries the download cleanly:

```powershell
terraform init
```

If it keeps timing out, force a clean retry:

```powershell
Remove-Item -Recurse -Force .terraform
terraform init
```

**Prevention**
Run `terraform init` on a stable connection. The download only
happens once — subsequent inits reuse the cached provider from
`.terraform/providers/`.

---

### 3. Deprecated dynamodb_table Parameter

**Phase:** 0 — Remote State Backend

**Symptom**
```
Warning: Deprecated Parameter
  on backend.tf line 6, in terraform:
   6:     dynamodb_table = "project102-terraform-dynamodb-locks"
The parameter "dynamodb_table" is deprecated.
Use parameter "use_lockfile" instead.
```

**Cause**
Terraform AWS provider v5.x introduced a native S3 lock file mechanism.
The old approach required a separate DynamoDB table for state locking.
The new approach stores the lock directly in S3 as a `.tflock` file —
simpler and cheaper (no DynamoDB table needed).

**Fix**
Update `backend.tf` — replace `dynamodb_table` with `use_lockfile`:

```hcl
# Before (deprecated):
terraform {
  backend "s3" {
    bucket         = "project102-terraform-state-XXXX"
    key            = "project102/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "project102-terraform-locks"
    encrypt        = true
  }
}

# After (current):
terraform {
  backend "s3" {
    bucket       = "project102-terraform-state-XXXX"
    key          = "project102/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

Then reinitialize:
```powershell
terraform init -reconfigure
```

Delete the now-unused DynamoDB table in the AWS Console:
AWS Console → DynamoDB → Tables → select table → Delete

**Prevention**
Check Terraform provider changelog when upgrading versions.
Run `terraform init -upgrade` periodically to catch deprecation
warnings early.

---

### 4. variable.tf Named Incorrectly

**Phase:** 0 — Terraform Skeleton

**Symptom**
File committed to Git as `variable.tf` instead of `variables.tf`.
Inconsistent with Terraform community conventions.

**Cause**
Typo during initial file creation.

**Fix**
Rename using git mv to preserve history:

```powershell
git mv variable.tf variables.tf
git add .
git commit -m "Fix: rename variable.tf to variables.tf"
git push origin main
```

**Prevention**
Standard Terraform file naming convention:
- `main.tf` — provider + terraform block
- `variables.tf` — input variables (plural)
- `outputs.tf` — output values (plural)
- `backend.tf` — remote state configuration
- `s3.tf`, `iam.tf`, `vpc.tf` — resources grouped by service

---

### 5. gitattributes Invalid Attribute Warning

**Phase:** 0 — Git Configuration

**Symptom**
```
.gitattributes" is not a valid attribute name: .gitattributes:16
```

**Cause**
PowerShell's `Out-File` with heredoc syntax added a trailing quote
character or invisible character at line 16 of the `.gitattributes`
file, creating an invalid attribute name.

**Fix**
Open `.gitattributes` in VS Code, delete all content, and retype
manually (do not copy-paste from chat):

```
* text=auto
*.py text eol=lf
*.tf text eol=lf
*.md text eol=lf
*.json text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
```

Save → commit → push.

**Prevention**
Always verify file contents with `cat .gitattributes` after
creating config files via PowerShell heredoc. Special characters
can be silently injected by the shell.

---

### 6. LF Will Be Replaced by CRLF Warning

**Phase:** 0 — Git Push

**Symptom**
```
warning: in the working copy of 'PROJECT_CONTEXT_Mermaid.md',
LF will be replaced by CRLF the next time Git touches it
```

**Cause**
Windows uses CRLF (`\r\n`) line endings. Linux/Mac use LF (`\n`).
Files created on Windows get CRLF; files created on Linux/Mac get LF.
When Git on Windows checks in a LF file, it warns that it will
convert it.

**Fix**
Add a `.gitattributes` file to normalize line endings:

```
* text=auto
*.py text eol=lf
*.tf text eol=lf
*.md text eol=lf
*.json text eol=lf
```

`text=auto` tells Git to handle conversion automatically.
`eol=lf` forces specific file types to always use LF in the repo.

**Prevention**
Add `.gitattributes` at the very start of every project before
the first commit. This is a one-time setup that prevents all
future LF/CRLF noise.

---

## Phase 1 — Storage Layer

---

### 7. Invalid Resource Type aws_s3_lifecycle_configuration

**Phase:** 1 — S3 Buckets

**Symptom**
```
Error: Invalid resource type
  on s3.tf line 42, in resource "aws_s3_lifecycle_configuration" "bronze":
  42: resource "aws_s3_lifecycle_configuration" "bronze" {
The provider hashicorp/aws does not support resource type
"aws_s3_lifecycle_configuration".
```

**Cause**
Wrong resource type name used. The AWS Terraform provider uses
`aws_s3_bucket_lifecycle_configuration` — it requires `bucket_`
in the middle of the name.

**Fix**
In `s3.tf` rename the resource:

```hcl
# Before (wrong):
resource "aws_s3_lifecycle_configuration" "bronze" {

# After (correct):
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
```

**General rule**
Most S3-related Terraform resources follow the pattern:
`aws_s3_bucket_<feature>` — for example:
- `aws_s3_bucket_versioning`
- `aws_s3_bucket_public_access_block`
- `aws_s3_bucket_lifecycle_configuration`
- `aws_s3_bucket_policy`

When in doubt run `terraform providers schema` or check the
Terraform AWS provider docs at
`registry.terraform.io/providers/hashicorp/aws/latest/docs`.

---

### 8. Lifecycle Rule Missing Filter Block

**Phase:** 1 — S3 Lifecycle Configuration

**Symptom**
```
Warning: Invalid Attribute Combination
  with aws_s3_bucket_lifecycle_configuration.bronze,
  on s3.tf line 45, in resource "aws_s3_bucket_lifecycle_configuration" "bronze":
  45:   rule {
No attribute specified when one (and only one) of
[rule[0].filter, rule[0].prefix] is required
This will be an error in a future version of the provider
```

**Cause**
AWS S3 lifecycle rules require a `filter` block to specify which
objects the rule applies to. Without it, the provider does not know
the scope of the rule. In older provider versions this defaulted to
all objects — in v5.x it is required explicitly.

**Fix**
Add an empty `filter` block with `prefix = ""` to match all objects:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    id     = "move-to-glacier"
    status = "Enabled"

    filter {
      prefix = ""    # empty string = apply to ALL objects in bucket
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }
  }
}
```

**Prevention**
Always include a `filter` block in lifecycle rules even when
targeting all objects. Explicit is better than implicit —
this matches the direction the provider is moving.

---

### 9. InvalidTag — Em Dash in Tag Values

**Phase:** 1 — S3 Bucket Tags

**Symptom**
```
Error: setting S3 Bucket (project102-bronze-raw) tags:
api error InvalidTag: The TagValue you have provided is invalid
```

**Cause**
AWS S3 tag values only accept basic ASCII characters. The em dash
character `—` (Unicode U+2014) copied from a chat interface was
used in the Description tag value:

```hcl
# This fails — em dash is not ASCII:
Description = "Raw JSON from World Bank API — untouched"
```

**Fix**
Replace em dash `—` with a plain ASCII hyphen `-`:

```hcl
# This works:
Description = "Raw JSON from World Bank API - untouched"
```

**General rule**
AWS tag values must be plain ASCII. Characters that commonly
cause this issue:
- Em dash `—` (U+2014) — use `-` instead
- En dash `–` (U+2013) — use `-` instead
- Smart quotes `"` `"` — use `"` instead
- Ellipsis `…` (U+2026) — use `...` instead
- Any Unicode character above U+007F

**Prevention**
Never copy-paste tag values directly from chat interfaces, Word
documents, or websites. Type tag values manually in VS Code to
ensure plain ASCII characters only.

---

### 10. InvalidTag — Box Drawing Characters in Comments

**Phase:** 1 — S3 Bucket Tags

**Symptom**
```
Error: setting S3 Bucket (project102-gold-analytics) tags:
api error InvalidTag: The TagValue you have provided is invalid
```

Gold bucket kept failing even after fixing the em dash. The
Description tag looked clean in the terminal but the error persisted.

**Cause**
The HCL comment separator lines used box-drawing characters
(Unicode U+2500 `─`) which appeared as `â"€` when the file
encoding was misread:

```hcl
# ──────────────────────────────────────────────
# GOLD BUCKET - Dimensional Parquet (Analytics)
# ──────────────────────────────────────────────
```

AWS rejected the entire bucket resource block because these
non-ASCII characters existed anywhere in the associated `.tf` file.

**Diagnosis**
Run this to find all non-ASCII characters in a file:

```powershell
$content = Get-Content s3.tf -Raw
$content | ForEach-Object {
    $chars = $_.ToCharArray()
    $chars | ForEach-Object {
        if ([int]$_ -gt 127) {
            Write-Host "Non-ASCII: '$_' (code: $([int]$_))"
        }
    }
}
```

**Fix**
In VS Code use Find and Replace (`Ctrl+H`):
- Find: `──────────────────────────────────────────────`
- Replace: `----------------------------------------------`
- Click Replace All

Replace ALL decorative separator lines throughout the file.

**Prevention**
Use only plain ASCII characters in `.tf` files:
- Comments: use `#` with plain `-` for separators
- No box-drawing characters, no Unicode decorations
- Set VS Code to show non-printable characters:
  View → Render Whitespace → helps spot invisible characters

---

### 11. Terraform Init Run from Wrong Directory

**Phase:** 0 — Terraform Initialization

**Symptom**
```
Terraform initialized in an empty directory!
The directory has no Terraform configuration files.
```

**Cause**
`terraform init` was run from the repo root
(`Project102_AWS_Pipeline/`) instead of the terraform directory
(`Project102_AWS_Pipeline/infrastructure/terraform/`).

**Fix**
Always navigate to the terraform directory before running any
Terraform commands:

```powershell
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

**Prevention**
Check your prompt before running Terraform commands. The path
should always end with `infrastructure/terraform`. Add this
check as a habit:

```powershell
# Verify you are in the right place
pwd
# Should show: ...Project102_AWS_Pipeline\infrastructure\terraform
```

---

## Prevention Tips Summary

1. **ASCII only in .tf files** — no em dashes, box-drawing characters,
   smart quotes, or any Unicode above U+007F in resource configurations
   or tag values.

2. **Always run terraform plan before apply** — read every `+`, `~`,
   `-` symbol before typing yes. If something unexpected shows up, stop
   and investigate.

3. **Check your directory before Terraform commands** — `pwd` should
   always show `infrastructure/terraform`.

4. **Add .gitattributes at project start** — prevents LF/CRLF noise
   on every subsequent push.

5. **Terraform resource names follow patterns** — S3 resources are
   `aws_s3_bucket_<feature>`. When unsure check
   `registry.terraform.io/providers/hashicorp/aws/latest/docs`.

6. **State management picks up where it left off** — if `apply` fails
   halfway, fix the error and run `apply` again. Terraform skips
   resources already created. Never manually delete partially-created
   resources unless you also run `terraform state rm`.

7. **Remote state is your safety net** — the S3 backend means your
   state is safe even if your laptop dies. Always confirm
   `Successfully configured the backend "s3"` during init.

8. **Tag values are validated by AWS** — test tag values mentally
   against ASCII-only before applying. Description fields are the
   most common place special characters sneak in.

---

## Quick Reference — Terraform Commands

```powershell
# Initialize (first time or after backend change)
terraform init

# Initialize and migrate state to new backend
terraform init -migrate-state

# Initialize and force reconfigure
terraform init -reconfigure

# Preview changes without touching AWS
terraform plan

# Apply changes (always review plan output first)
terraform apply

# Destroy all resources (careful - irreversible)
terraform destroy

# Show current state
terraform show

# List resources in state
terraform state list

# Refresh outputs
terraform refresh
terraform output

# Validate syntax without connecting to AWS
terraform validate

# Format .tf files to standard style
terraform fmt

# Find non-ASCII characters in a file (PowerShell)
$content = Get-Content filename.tf -Raw
$content.ToCharArray() | Where-Object { [int]$_ -gt 127 } |
    ForEach-Object { Write-Host "Non-ASCII: '$_' (code: $([int]$_))" }
```

---

_Last updated: 2026-05-04_
_Status: Phase 0 complete ✅ | Phase 1 S3 complete ✅ | VPC + Secrets Manager pending_
_Project: Project102_AWS_Pipeline_
_Maintainer: Thierry — github.com/Thierry0326_
