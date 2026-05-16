terraform {
  backend "s3" {
    bucket         = "project102-s3-terraform-state"
    key            = "project102/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile = true
    encrypt        = true
  }
}