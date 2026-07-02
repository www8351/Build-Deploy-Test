variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "AMI id; empty resolves the latest Amazon Linux 2023 via SSM"
}

variable "app_port" {
  type        = number
  default     = 8351
  description = "Application ingress port (Nginx)"
}

variable "ssh_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach SSH"
}

variable "key_name" {
  type        = string
  default     = ""
  description = "EC2 key pair name (optional)"
}

variable "sg_name" {
  type        = string
  default     = "hardened-web-sg"
  description = "Security group name"
}

variable "tag_name" {
  type        = string
  default     = "hardened-web"
  description = "Name tag for the instance and SG"
}
