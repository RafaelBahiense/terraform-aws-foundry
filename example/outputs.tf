output "vpc_id" {
  value = module.foundry.vpc_id
}

output "subnet_id" {
  value = module.foundry.subnet_id
}

output "public_ip" {
  value = module.foundry.public_ip
}

output "id" {
  value = module.foundry.id
}

output "foundry_server" {
  value = module.foundry.foundry_server
}

output "public_key_openssh" {
  value = module.foundry.public_key_openssh
}

output "public_key" {
  value = module.foundry.public_key
}

output "private_key" {
  value = module.foundry.private_key
  sensitive = true
}

output "zzz_ec2_ssh" {
  value = module.foundry.zzz_ec2_ssh
}

