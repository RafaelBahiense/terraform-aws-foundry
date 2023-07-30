// Create a server using all defaults

provider "aws" {
  profile = "my-profile"
  region = "my-aws-region"
}

module "foundry" {
  source = "../"

  name        = "my-foundry-server"
  namespace   = "my-namespace"

  ami = "ami-053b0d53c279acc90" # Ubuntu 22.04 LTS
  instance_type = "t2.large"

  foundry_backup_freq = 10

  foundry_port = 80

  hostname_dynv6 = "my-domain.dynv6.net"
  token_dynv6    = "my-token"

  auto_shutdown_time = 0
}
