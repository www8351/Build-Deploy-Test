# OpenTofu twin of jobs/job15_aws_ec2_provision.sh: a hardened EC2 instance
# with IMDSv2 required and a least-open security group, as declarative IaC with
# managed state instead of an imperative shell script.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.al2023.value

  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y docker amazon-cloudwatch-agent
    systemctl enable --now docker
    sed -ri 's|^[[:space:]]*#?[[:space:]]*(PasswordAuthentication)\b.*|\1 no|I' /etc/ssh/sshd_config
    systemctl reload sshd || systemctl restart sshd
  EOT
}

resource "aws_security_group" "hardened_web" {
  name        = var.sg_name
  description = "hardened web sg (managed by OpenTofu)"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "app"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.tag_name
  }
}

resource "aws_instance" "hardened_web" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.hardened_web.id]
  user_data              = local.user_data
  key_name               = var.key_name != "" ? var.key_name : null

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 strictly enforced (blocks SSRF creds theft)
  }

  tags = {
    Name = var.tag_name
  }
}
