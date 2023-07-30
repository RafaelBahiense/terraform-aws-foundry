variable "vpc_id" {
  description = "VPC for security group"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "VPC subnet id to place the instance"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "EC2 key name for provisioning and access"
  type        = string
  default     = ""
}

variable "bucket_name" {
  description = "Bucket name for persisting foundry world"
  type        = string
  default     = ""
}

variable "bucket_force_destroy" {
  description = "A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error. This will destroy your foundry world!"
  type        = bool
  default     = false
}

variable "bucket_object_versioning" {
  description = "Enable object versioning (default = true). Note this may incur more cost."
  type        = bool
  default     = true
}

// For tags
variable "name" {
  description = "Name to use for servers, tags, etc (e.g. foundry)"
  type        = string
  default     = "foundry"
}

variable "namespace" {
  description = "Namespace, which could be your organization name or abbreviation, e.g. 'eg' or 'cp'"
  type        = string
  default     = "games"
}

variable "environment" {
  description = "Environment, e.g. 'prod', 'staging', 'dev', 'pre-prod', 'UAT'"
  type        = string
  default     = "games"
}

variable "tags" {
  description = "Any extra tags to assign to objects"
  type        = map
  default     = {}
}

// Minecraft-specific defaults
variable "foundry_port" {
  description = "TCP port for foundry"
  type        = number
  default     = 30000
}

variable "foundry_root" {
  description = "Where to install foundry on your instance"
  type        = string
  default     = "/home/foundry"
}

variable "foundry_url" {
  description = "URL to download foundry from"
  type        = string
  default     = ""
}

variable "foundry_version" {
  description = "Which version of foundry to install"
  type        = string
  default     = "latest"
}

variable "foundry_backup_freq" {
  description = "How often (mins) to sync to S3"
  type        = number
  default     = 5
}

// Instance vars
variable "associate_public_ip_address" {
  description = "By default, our server has a public IP"
  type        = bool
  default     = true
}

variable "ami" {
  description = "AMI to use for the instance - will default to latest Ubuntu"
  type        = string
  default     = ""
}

// https://aws.amazon.com/ec2/instance-types/
variable "instance_type" {
  description = "EC2 instance type/size - the default is not part of free tier!"
  type        = string
  default     = "t2.medium"
}

variable "allowed_cidrs" {
  description = "Allow these CIDR blocks to the server - default is the Universe"
  type        = string
  default     = "0.0.0.0/0"
}

variable "hostname_dynv6" {
  description = "Dynv6 hostname to update with the server's public IP"
  type        = string
  default     = ""
}

variable "token_dynv6" {
  description = "Dynv6 API token"
  type        = string
  default     = ""
}

variable "auto_shutdown_time" {
  description = "By default, our server has a public IP"
  type        = number
  default     = 0
}