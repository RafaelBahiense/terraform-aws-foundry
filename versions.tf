terraform {
  required_version = ">= 1.4.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.1.0"
    }
    template = "~> 2.1.2"
  }
}