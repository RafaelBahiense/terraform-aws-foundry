// This module creates a single EC2 instance for running a Foundry server

// Default network
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
     name   = "vpc-id"
     values = [local.vpc_id]
  }
}

data "aws_caller_identity" "aws" {}

locals {
  vpc_id    = length(var.vpc_id) > 0 ? var.vpc_id : data.aws_vpc.default.id
  subnet_id = length(var.subnet_id) > 0 ? var.subnet_id : sort(data.aws_subnets.default.ids)[0]
  tf_tags = {
    Terraform = true,
    By        = data.aws_caller_identity.aws.arn
  }
}

// Keep labels, tags consistent
module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=main"

  namespace   = var.namespace
  stage       = var.environment
  name        = var.name
  delimiter   = "-"
  label_order = ["environment", "stage", "name", "attributes"]
  tags        = merge(var.tags, local.tf_tags)
}

// Amazon Linux2 AMI - can switch this to default by editing the EC2 resource below
data "aws_ami" "amazon-linux-2" {
  most_recent = true

  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

// Find latest Ubuntu AMI, use as default if no AMI specified
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

// S3 bucket for persisting foundry world
resource "random_string" "s3" {
  length  = 12
  special = false
  upper   = false
}

locals {
  using_existing_bucket = signum(length(var.bucket_name)) == 1

  bucket = length(var.bucket_name) > 0 ? var.bucket_name : "${module.label.id}-${random_string.s3.result}"
}

module "s3" {
  source = "terraform-aws-modules/s3-bucket/aws"

  create_bucket = local.using_existing_bucket ? false : true

  bucket = local.bucket
  acl    = null

  force_destroy = var.bucket_force_destroy

  versioning = {
    enabled = var.bucket_object_versioning
  }

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  tags = module.label.tags
}

// IAM role for S3 access
resource "aws_iam_role" "allow_s3" {
  name   = "${module.label.id}-allow-ec2-to-s3"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "foundry" {
  name = "${module.label.id}-instance-profile"
  role = aws_iam_role.allow_s3.name
}

resource "aws_iam_role_policy" "foundry_allow_ec2_to_s3" {
  name   = "${module.label.id}-allow-ec2-to-s3"
  role   = aws_iam_role.allow_s3.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${local.bucket}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::${local.bucket}/*"]
    }
  ]
}
EOF
}

// Script to configure the server - this is where most of the magic occurs!
data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    foundry_root        = var.foundry_root
    foundry_port        = var.foundry_port
    foundry_bucket      = local.bucket
    foundry_backup_freq = var.foundry_backup_freq
    foundry_url         = var.foundry_url
    foundry_version     = var.foundry_version
    hostname_dynv6      = var.hostname_dynv6
    token_dynv6         = var.token_dynv6
    auto_shutdown_time  = var.auto_shutdown_time
  }
}

// Security group for our instance - allows SSH and Foundry Server
module "ec2_security_group" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=master"

  name        = "${var.name}-ec2"
  description = "Allow SSH and TCP ${var.foundry_port}"
  vpc_id      = local.vpc_id

  ingress_cidr_blocks      = [ var.allowed_cidrs ]
  ingress_rules            = [ "ssh-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = var.foundry_port
      to_port     = var.foundry_port
      protocol    = "tcp"
      description = "Foundry server"
      cidr_blocks = var.allowed_cidrs
    },
  ]
  egress_rules = ["all-all"]

  tags = module.label.tags
}

// Create EC2 ssh key pair
resource "tls_private_key" "ec2_ssh" {
  count = length(var.key_name) > 0 ? 0 : 1

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_ssh" {
  count = length(var.key_name) > 0 ? 0 : 1

  key_name   = "${var.name}-ec2-ssh-key"
  public_key = tls_private_key.ec2_ssh[0].public_key_openssh
}

locals {
  _ssh_key_name = length(var.key_name) > 0 ? var.key_name : aws_key_pair.ec2_ssh[0].key_name
}

// EC2 instance for the server - tune instance_type to fit your performance and budget requirements
module "ec2_foundry" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git?ref=master"
  name   = "${var.name}-public"

  # instance
  key_name             = local._ssh_key_name
  ami                  = var.ami != "" ? var.ami : data.aws_ami.ubuntu.image_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.foundry.id
  user_data            = data.template_file.user_data.rendered

  # network
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [ module.ec2_security_group.security_group_id ]
  associate_public_ip_address = var.associate_public_ip_address

  tags = module.label.tags
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "ec2_stop_policy" {
  count = var.auto_shutdown_time > 0 ? 1 : 0

  statement {
    actions   = ["ec2:StopInstances"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${module.ec2_foundry.id}"]
  }
}

resource "aws_iam_role_policy" "ec2_stop_policy" {
  count = var.auto_shutdown_time > 0 ? 1 : 0

  name   = "EC2StopPolicy"
  role   = aws_iam_role.allow_s3.id
  policy = data.aws_iam_policy_document.ec2_stop_policy[0].json
}