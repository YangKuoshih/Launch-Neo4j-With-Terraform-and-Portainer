###############################
# VARIABLES
###############################
variable "region" {}
variable "allowed_source_ips" {}
variable "project_id" {}
variable "ami" {}
variable "instance_type" {}
variable "availability_zone" {}

###############################
# PROVIDER & DATA SOURCES
###############################
provider "aws" {
  region = var.region
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

data "http" "my_public_ip" {
  url = "https://api.ipify.org"
  request_headers = {
    Accept = "application/text"
  }
}

###############################
# NETWORKING: VPC, SUBNET, IGW, ROUTE TABLE
###############################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_id}-main-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone

  tags = {
    Name = "${var.project_id}-public-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_id}-main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

###############################
# LOCAL VARIABLES
###############################
locals {
  my_ip         = "${chomp(data.http.my_public_ip.response_body)}/32"
  all_allowed_ips = concat(var.allowed_source_ips, [local.my_ip])
}

###############################
# SECURITY GROUP
###############################
resource "aws_security_group" "allow_sources" {
  name        = "${var.project_id}_allow_sources"
  description = "Allow SSH and application inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed sources"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.all_allowed_ips
  }

  ingress {
    description = "Caddy main-range (6000-6999)"
    from_port   = 6000
    to_port     = 6999
    protocol    = "tcp"
    cidr_blocks = local.all_allowed_ips
  }

  ingress {
    description = "Neo4j 7474"
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = local.all_allowed_ips
  }

  ingress {
    description = "Neo4j Bolt (7687)"
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = local.all_allowed_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.project_id}_allow_sources"
    CreatedBy = "terraform"
  }
}

###############################
# IAM ROLES & INSTANCE PROFILE
###############################
resource "aws_iam_role" "dev_role" {
  name = "${var.project_id}_dev_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "ec2.amazonaws.com",
          "lambda.amazonaws.com"
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = "${var.project_id}_dev_role"
    CreatedBy = "terraform"
  }
}

resource "aws_iam_policy" "dev_role_policy" {
  name        = "${var.project_id}_dev_role_policy"
  description = "Policy for Dev access"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "*",
      Resource = "*"
    }]
  })

  tags = {
    Name      = "${var.project_id}_dev_role_policy"
    CreatedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "attach_dev_role_policy" {
  policy_arn = aws_iam_policy.dev_role_policy.arn
  role       = aws_iam_role.dev_role.name
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.project_id}-instance-profile"
  role = aws_iam_role.dev_role.name

  tags = {
    Name      = "${var.project_id}-instance-profile"
    CreatedBy = "terraform"
  }
}

###############################
# KEY PAIR & TLS PRIVATE KEY
###############################
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.this.private_key_pem
  filename = "..\\keys\\private_key.pem"
}

resource "local_file" "public_key" {
  content  = tls_private_key.this.public_key_openssh
  filename = "..\\keys\\public_key.pub"
}

resource "aws_key_pair" "main_key" {
  key_name   = "${var.project_id}_key_pair"
  public_key = tls_private_key.this.public_key_openssh
  tags = {
    Name      = "${var.project_id}_key_pair"
    CreatedBy = "terraform"
  }
}

###############################
# S3 BUCKET & ZIP UPLOAD MODULES
###############################
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "data_bucket" {
  bucket        = "${var.project_id}-data-${random_string.bucket_suffix.result}"
  force_destroy = true
}

module "caddy_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "caddy"
  source_dir      = "${path.module}/../caddy"
  output_filename = "caddy.zip"
}

module "docker_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "docker"
  source_dir      = "${path.module}/../docker"
  output_filename = "docker.zip"
}

module "scripts_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "scripts"
  source_dir      = "${path.module}/../scripts"
  output_filename = "scripts.zip"
}

module "ec2-setup_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "ec2-setup"
  source_dir      = "${path.module}/../ec2-setup"
  output_filename = "ec2-setup.zip"
}

# module "web-apps_zip_upload" {
#   source          = "./modules/zip_and_upload_to_s3"
#   bucket_name     = aws_s3_bucket.data_bucket.id
#   folder_name     = "web-apps"
#   source_dir      = "${path.module}/../web-apps"
#   output_filename = "web-apps.zip"
# }

# module "ansible_zip_upload" {
#   source          = "./modules/zip_and_upload_to_s3"
#   bucket_name     = aws_s3_bucket.data_bucket.id
#   folder_name     = "ansible"
#   source_dir      = "${path.module}/../ansible"
#   output_filename = "ansible.zip"
# }

# module "code-server-extensions_zip_upload" {
#   source          = "./modules/zip_and_upload_to_s3"
#   bucket_name     = aws_s3_bucket.data_bucket.id
#   folder_name     = "code-server-extensions"
#   source_dir      = "${path.module}/../code-server-extensions"
#   output_filename = "code-server-extensions.zip"
# }

###############################
# USER DATA & EC2 INSTANCE
###############################
locals {
  user_data_script = file("${path.module}/../ec2-setup/user-data.sh")
  ec2_user_data = <<-EOT
    #!/bin/bash
    export PROJECT_ID=${var.project_id}
    export AWS_REGION=${data.aws_region.current.name}
    export DATA_BUCKET_NAME=${aws_s3_bucket.data_bucket.id}
    
    ${local.user_data_script}
  EOT
}

resource "aws_s3_object" "ec2_setup_script" {
  bucket       = aws_s3_bucket.data_bucket.id
  key          = "ec2-setup.sh"
  content      = local.ec2_user_data
  content_type = "text/x-shellscript"
}

resource "aws_instance" "main_instance" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = aws_key_pair.main_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  vpc_security_group_ids      = [aws_security_group.allow_sources.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    aws s3 cp s3://${aws_s3_bucket.data_bucket.id}/ec2-setup.sh /root/
    chmod +x /root/ec2-setup.sh
    sudo yum install dos2unix -y
    dos2unix /root/ec2-setup.sh
    /root/ec2-setup.sh
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = 2048
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_s3_bucket.data_bucket,
    aws_s3_object.ec2_setup_script
  ]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name          = "${var.project_id}_main_server"
    CreatedBy     = "terraform"
    AutoStopStart = "True"
  }
}

resource "aws_eip" "dev_ec2_eip" {
  instance = aws_instance.main_instance.id
  tags = {
    Name      = "${var.project_id}_dev_ec2_eip"
    CreatedBy = "terraform"
  }
}

###############################
# LAMBDA & CONTROLLER SETUP
###############################
# resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
#   role       = aws_iam_role.dev_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# data "archive_file" "controller_lambda_zip" {
#   type        = "zip"
#   output_path = "${path.module}/../lambda/function.zip"
#   source_dir  = "${path.module}/../lambda/controller"
# }

# data "archive_file" "layer_zip" {
#   type        = "zip"
#   source_dir  = "${path.module}/../lambda/layer/package"
#   output_path = "${path.module}/../lambda/layer.zip"
# }

# resource "aws_lambda_layer_version" "common_layer" {
#   layer_name          = "common-layer"
#   filename            = data.archive_file.layer_zip.output_path
#   compatible_runtimes = ["python3.8", "python3.9"]
#   description         = "Common Lambda Layer for shared dependencies"
# }

resource "random_string" "controller_jwt_secret_key" {
  length  = 24
  special = false
  upper   = false
}

# resource "aws_lambda_function" "main_controller_lambda" {
#   filename         = data.archive_file.controller_lambda_zip.output_path
#   function_name    = "${var.project_id}-controller"
#   role             = aws_iam_role.dev_role.arn
#   handler          = "main.lambda_handler"
#   runtime          = "python3.12"
#   source_code_hash = data.archive_file.controller_lambda_zip.output_base64sha256
#   timeout          = 60

#   layers = [aws_lambda_layer_version.common_layer.arn]

#   tags = {
#     Name      = "${var.project_id}-controller"
#     CreatedBy = "terraform"
#   }
# }

# resource "aws_lambda_function_url" "controller_lambda_url" {
#   function_name      = aws_lambda_function.main_controller_lambda.function_name
#   authorization_type = "NONE"

#   cors {
#     allow_credentials = true
#     allow_origins     = ["*"]
#     allow_methods     = ["*"]
#     allow_headers     = ["date", "keep-alive"]
#     expose_headers    = ["keep-alive", "date"]
#     max_age           = 86400
#   }
# }

###############################
# SCHEDULER & INSTANCE AUTO STOP/START
###############################
data "aws_instances" "tagged_instances" {
  filter {
    name   = "tag:AutoStopStart"
    values = ["True"]
  }
  depends_on = [ aws_instance.main_instance ]
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
  schedule_expression = "cron(0 0 * * ? *)"
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler_role.arn
    input    = jsonencode({ InstanceIds = data.aws_instances.tagged_instances.ids })
  }
}

resource "aws_scheduler_schedule" "start_ec2" {
  name       = "${var.project_id}-start-ec2-schedule"
  group_name = "default"
  state      = "DISABLED"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "cron(0 4 * * ? *)"
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

# output "controller_url" {
#   value       = aws_lambda_function_url.controller_lambda_url.function_url
# }

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

resource "aws_ssm_parameter" "resource_ids" {
  name  = "/${var.project_id}/info"
  type  = "String"
  value = jsonencode({
    elasticIP                 = aws_eip.dev_ec2_eip.public_ip,
    projectId                 = var.project_id,
    instanceId                = aws_instance.main_instance.id,
    # controllerUrl             = aws_lambda_function_url.controller_lambda_url.function_url,
    dataBucketName            = aws_s3_bucket.data_bucket.id,
    controller_jwt_secret_key = random_string.controller_jwt_secret_key.result,
    ec2SecurityGroupId        = aws_security_group.allow_sources.id,
    ec2PublicDns              = aws_instance.main_instance.public_dns,
    eipPublicDns              = aws_eip.dev_ec2_eip.public_dns
  })

  depends_on = [
    aws_eip.dev_ec2_eip,
    aws_instance.main_instance,
    # aws_lambda_function_url.controller_lambda_url,
    aws_s3_bucket.data_bucket,
    random_string.controller_jwt_secret_key
  ]
}

resource "local_file" "outputs" {
  filename = "${path.module}/set-tf-output-2-env-var.bat"
  content  = <<-EOT
    set AWS_REGION=${data.aws_region.current.name}
    set ELASTIC_IP=${aws_eip.dev_ec2_eip.public_ip}
    set PROJECT_ID=${var.project_id}
    set INSTANCE_ID=${aws_instance.main_instance.id}
    set EIP_PUBLIC_DNS=${aws_eip.dev_ec2_eip.public_dns}
    set EC2_PUBLIC_DNS=${aws_instance.main_instance.public_dns}
    set DATA_BUCKET_NAME=${aws_s3_bucket.data_bucket.id}
    set EC2_SECURITY_GROUP_ID=${aws_security_group.allow_sources.id}
  EOT
}

# set CONTROLLER_URL=${aws_lambda_function_url.controller_lambda_url.function_url}
    