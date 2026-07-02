#!/usr/bin/env bash
#
# JOB 15 - provision a hardened EC2 instance with the AWS CLI v2.
# Jenkins: "Execute shell" build step. Needs AWS credentials in the environment.
#   AWS_REGION    - target region                 (default: us-east-1)
#   AMI_ID        - AMI to launch; empty = resolve latest AL2023 via SSM
#   INSTANCE_TYPE - instance size                 (default: t3.micro)
#   SG_NAME       - security group name           (default: hardened-web-sg)
#   APP_PORT      - app ingress port              (default: 8351)
#   SSH_CIDR      - CIDR allowed to reach SSH      (default: 0.0.0.0/0)
#   KEY_NAME      - EC2 key pair name             (optional)
#   TAG_NAME      - Name tag                       (default: hardened-web)
#   DRY_RUN       - if set, print plan + user-data and exit (no AWS calls)
#
# Creates a least-open security group, launches an instance with IMDSv2
# STRICTLY required (HttpTokens=required — blocks SSRF creds theft), and injects
# a base64 user-data script that installs Docker + the CloudWatch agent and
# locks the box down on first boot. The public IP is extracted via JMESPath.
#
set -Eeuo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AMI_ID="${AMI_ID:-}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
SG_NAME="${SG_NAME:-hardened-web-sg}"
APP_PORT="${APP_PORT:-8351}"
SSH_CIDR="${SSH_CIDR:-0.0.0.0/0}"
KEY_NAME="${KEY_NAME:-}"
TAG_NAME="${TAG_NAME:-hardened-web}"
DRY_RUN="${DRY_RUN:-}"

trap 'echo "ERR: failed at line $LINENO" >&2' ERR

# First-boot hardening script baked into user-data (quoted heredoc: no local
# expansion — it runs on the instance, not here).
build_user_data() {
  cat <<'UD'
#!/bin/bash
set -euo pipefail
dnf update -y
dnf install -y docker amazon-cloudwatch-agent
systemctl enable --now docker
# minimal lockdown: disable password SSH, enforce key-only
sed -ri 's|^[[:space:]]*#?[[:space:]]*(PasswordAuthentication)\b.*|\1 no|I' /etc/ssh/sshd_config
sed -ri 's|^[[:space:]]*#?[[:space:]]*(PermitRootLogin)\b.*|\1 no|I' /etc/ssh/sshd_config
systemctl reload sshd || systemctl restart sshd
UD
}

aws_cli() { aws --region "$AWS_REGION" "$@"; }

USER_DATA_B64="$(build_user_data | base64 -w0)"

if [ -n "$DRY_RUN" ]; then
  echo "--- DRY_RUN: plan (no AWS calls) ---"
  echo "region=$AWS_REGION type=$INSTANCE_TYPE sg=$SG_NAME app_port=$APP_PORT"
  echo "ami=${AMI_ID:-<resolve latest AL2023 via SSM>}"
  echo "run-instances --metadata-options HttpTokens=required,HttpEndpoint=enabled"
  echo "user-data (base64, ${#USER_DATA_B64} chars):"
  echo "$USER_DATA_B64"
  echo "--- decoded user-data ---"
  echo "$USER_DATA_B64" | base64 -d
  echo "Done: dry run."
  exit 0
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found." >&2; exit 1; }

# Resolve the latest Amazon Linux 2023 AMI if none was pinned.
if [ -z "$AMI_ID" ]; then
  AMI_ID="$(aws_cli ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameter.Value' --output text)"
fi
echo "AMI: $AMI_ID"

# Least-open security group: SSH from SSH_CIDR, app port from anywhere.
SG_ID="$(aws_cli ec2 create-security-group \
  --group-name "$SG_NAME" --description "hardened web sg" \
  --query 'GroupId' --output text)"
aws_cli ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$SSH_CIDR" >/dev/null
aws_cli ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port "$APP_PORT" --cidr 0.0.0.0/0 >/dev/null
echo "Security group: $SG_ID"

# Launch with IMDSv2 required and the base64 user-data.
KEY_ARGS=()
[ -n "$KEY_NAME" ] && KEY_ARGS=(--key-name "$KEY_NAME")
IID="$(aws_cli ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --security-group-ids "$SG_ID" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --user-data "$USER_DATA_B64" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TAG_NAME}]" \
  "${KEY_ARGS[@]}" \
  --query 'Instances[0].InstanceId' --output text)"
echo "Instance: $IID"

aws_cli ec2 wait instance-running --instance-ids "$IID"

# Robust public IP extraction; guard the "None" JMESPath result.
PUBLIC_IP="$(aws_cli ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
  echo "Instance $IID has no public IP (private subnet?)." >&2
else
  echo "Done: $IID running at $PUBLIC_IP"
fi
