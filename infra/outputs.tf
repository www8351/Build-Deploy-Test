output "instance_id" {
  value       = aws_instance.hardened_web.id
  description = "EC2 instance id"
}

output "public_ip" {
  value       = aws_instance.hardened_web.public_ip
  description = "Public IP of the instance (null in a private subnet)"
}

output "security_group_id" {
  value       = aws_security_group.hardened_web.id
  description = "Id of the hardened security group"
}
