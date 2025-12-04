###############################
# LAMBDA & CONTROLLER SETUP
###############################
resource "random_string" "controller_jwt_secret_key" {
  length  = 24
  special = false
  upper   = false
}

###############################
# SCHEDULER & INSTANCE AUTO STOP/START
###############################
data "aws_instances" "tagged_instances" {
  filter {
    name   = "tag:AutoStopStart"
    values = ["True"]
  }
  depends_on = [aws_instance.main_instance]
}

resource "aws_iam_role" "scheduler_role" {
  name = "${var.project_id}-ec2-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_policy" {
  name = "${var.project_id}-ec2-scheduler-policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "ec2:StartInstances",
        "ec2:StopInstances"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_scheduler_schedule" "stop_ec2" {
  name       = "${var.project_id}-stop-ec2-schedule"
  group_name = "default"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "cron(0 3 * * ? *)"
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler_role.arn
    input    = jsonencode({ InstanceIds = data.aws_instances.tagged_instances.ids })
  }
}

resource "aws_scheduler_schedule" "start_ec2" {
  name       = "${var.project_id}-start-ec2-schedule"
  group_name = "default"
  state      = "ENABLED"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "cron(0 12 * * ? *)"
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler_role.arn
    input    = jsonencode({ InstanceIds = data.aws_instances.tagged_instances.ids })
  }
}

###############################
# OUTPUTS & SSM PARAMETERS
###############################
output "subnet_id" {
  description = "The ID of the created public subnet"
  value       = aws_subnet.public.id
}

output "route_table_id" {
  description = "The ID of the created route table"
  value       = aws_route_table.public_rt.id
}

output "security_group_id" {
  description = "The ID of the created security group"
  value       = aws_security_group.allow_sources.id
}

output "iam_role_arn" {
  description = "The ARN of the created IAM role"
  value       = aws_iam_role.dev_role.arn
}

output "iam_policy_arn" {
  description = "The ARN of the created IAM policy"
  value       = aws_iam_policy.dev_role_policy.arn
}

output "instance_profile_arn" {
  description = "The ARN of the created IAM instance profile"
  value       = aws_iam_instance_profile.instance_profile.arn
}

output "key_pair_name" {
  description = "The name of the created key pair"
  value       = aws_key_pair.main_key.key_name
}

output "instance_id" {
  description = "The ID of the created EC2 instance"
  value       = aws_instance.main_instance.id
}

output "instance_public_ip" {
  description = "The public IP address of the created EC2 instance"
  value       = aws_instance.main_instance.public_ip
}

output "instance_private_ip" {
  description = "The private IP address of the created EC2 instance"
  value       = aws_instance.main_instance.private_ip
}

output "elastic_ip" {
  description = "The Elastic IP address associated with the EC2 instance"
  value       = aws_eip.dev_ec2_eip.public_ip
}

output "PROJECT_ID" {
  value = var.project_id
}

output "bucket_name" {
  value       = aws_s3_bucket.data_bucket.id
  description = "The name of the S3 bucket"
}

output "my_public_ip" {
  value       = data.http.my_public_ip.response_body
  description = "My public IP address"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

resource "aws_ssm_parameter" "resource_ids" {
  name  = "/${var.project_id}/info"
  type  = "SecureString"
  value = jsonencode({
    elasticIP                 = aws_eip.dev_ec2_eip.public_ip,
    projectId                 = var.project_id,
    instanceId                = aws_instance.main_instance.id,
    dataBucketName            = aws_s3_bucket.data_bucket.id,
    neo4j_secret_arn          = aws_secretsmanager_secret.neo4j_credentials.arn,
    jwt_secret_arn            = aws_secretsmanager_secret.jwt_secret.arn,
    ec2SecurityGroupId        = aws_security_group.allow_sources.id,
    ec2PublicDns              = aws_instance.main_instance.public_dns,
    eipPublicDns              = aws_eip.dev_ec2_eip.public_dns
  })

  depends_on = [
    aws_eip.dev_ec2_eip,
    aws_instance.main_instance,
    aws_s3_bucket.data_bucket,
    aws_secretsmanager_secret.neo4j_credentials,
    aws_secretsmanager_secret.jwt_secret
  ]
}

resource "local_file" "outputs" {
  filename = "${path.module}/set-tf-output-2-env-var.bat"
  content  = <<-EOT
    set AWS_REGION=${data.aws_region.current.name}
    set PROJECT_ID=${var.project_id}
    REM Use 'aws ssm get-parameter --name /${var.project_id}/info --with-decryption' to get sensitive values
    echo "To get instance details, run: aws ssm get-parameter --name /${var.project_id}/info --with-decryption"
  EOT
}

resource "local_file" "launcher" {
  filename = "${path.module}/../launcher.bat"
  content  = <<-EOT
    @echo off
    set ELASTIC_IP=${aws_eip.dev_ec2_eip.public_ip}
    set INSTANCE_ID=${aws_instance.main_instance.id}
    set PROJECT_ID=${var.project_id}
    set SSH_KEY=${path.module}/../keys/private_key.pem
    
    echo ===== Neo4j Enterprise Launcher =====
    echo Neo4j Browser: http://%ELASTIC_IP%:7474
    echo NeoDash: http://%ELASTIC_IP%:5005
    echo Portainer: https://%ELASTIC_IP%:8102
    echo Instance ID: %INSTANCE_ID%
    echo.
    echo ===== Shortcuts =====
    echo tfa = Terraform apply
    echo tfd = Terraform destroy
    echo cdd = CD to project directory
    echo sshe = SSH into EC2
    echo ec2 = Start EC2
    echo ec2x = Stop EC2
    echo neo4j = Opens Neo4j in Browser
    echo neodash = Opens NeoDash in Browser
    echo portainer = Opens Portainer in Browser
    echo esl = See EC2 setup logs
    echo tec2 = Taint ec2 and destroy and recreate it
    echo rkh = Host key info (auto-handled)
    echo.
    
    doskey tfa=cd /d "${path.module}" $T terraform apply
    doskey tfd=cd /d "${path.module}" $T terraform destroy
    doskey cdd=cd /d "${path.module}/.."
    doskey sshe=ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@%ELASTIC_IP%
    doskey ec2=aws ec2 start-instances --instance-ids %INSTANCE_ID%
    doskey ec2x=aws ec2 stop-instances --instance-ids %INSTANCE_ID%
    doskey neo4j=start http://%ELASTIC_IP%:7474
    doskey neodash=start http://%ELASTIC_IP%:5005
    doskey portainer=start https://%ELASTIC_IP%:8102
    doskey esl=ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@%ELASTIC_IP% "sudo tail -f /var/log/user-data.log"
    doskey tec2=cd /d "${path.module}" $T terraform taint aws_instance.main_instance $T terraform apply
    doskey rkh=echo "Host key checking disabled - no need to remove hosts"
    
    cmd /k
  EOT
}