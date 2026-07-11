# vpc.tf
# Creates the private network for Project 102
#
# Project 101 equivalent: Docker network created by docker-compose.yml
# What AWS adds: spans multiple data centers, fine-grained routing rules,
# security groups control traffic at resource level
#
# STATUS (Phase 3): built but NOT yet attached to the Glue jobs (glue.tf has
# no `connections` block referencing aws_security_group.glue / the private
# subnets). This is intentional for now, not a bug - job_bronze_ingest.py
# calls the public World Bank API, and these private subnets have no NAT/IGW,
# so Bronze Ingest cannot run fully private without adding a NAT Gateway
# (~$32/mo). Revisit if/when network hardening is worth that cost.
# Known follow-up if you do wire this up later: aws_vpc_endpoint.s3 below has
# no route_table_ids, so it isn't associated with any route table yet either.

# ----------------------------------------------
# VPC - The private network container
# ----------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Description = "Private network for Project 102 Glue jobs"
  }
}

# ----------------------------------------------
# PRIVATE SUBNETS
# Glue jobs run in private subnets - no direct
# internet access, traffic to S3 goes via endpoint
# ----------------------------------------------
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Description = "Private subnet 1 for Glue jobs"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project_name}-private-subnet-2"
    Description = "Private subnet 2 for Glue jobs - redundancy"
  }
}

# ----------------------------------------------
# S3 GATEWAY ENDPOINT
# Routes S3 traffic through AWS backbone - FREE
# Without this: traffic goes via NAT Gateway = $32/month
# With this: traffic stays on AWS network = $0
# ----------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    Description = "S3 Gateway Endpoint - free S3 access from VPC"
  }
}

# ----------------------------------------------
# SECURITY GROUP FOR GLUE
# Controls what traffic Glue jobs can send/receive
# Like a firewall around each Glue job
# ----------------------------------------------
resource "aws_security_group" "glue" {
  name        = "${var.project_name}-glue-sg"
  description = "Security group for Project 102 Glue jobs"
  vpc_id      = aws_vpc.main.id

  # HTTPS-only outbound - everything this SG's jobs talk to (S3, Secrets
  # Manager, CloudWatch Logs, and the World Bank API for Bronze Ingest) is
  # HTTPS. Narrowed from all-ports/all-protocols so a compromised job
  # environment can't open arbitrary outbound connections.
  #
  # 0.0.0.0/0 as a *destination* is still required and unavoidable here -
  # none of those endpoints have fixed/predictable IPs to pin to, and this
  # SG isn't currently attached to anything anyway (see the file header).
  # trivy:ignore:AWS-0104
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound only - AWS service APIs + World Bank API, no fixed destination IPs available"
  }

  tags = {
    Name        = "${var.project_name}-glue-sg"
    Description = "Security group for Glue ETL jobs"
  }
}