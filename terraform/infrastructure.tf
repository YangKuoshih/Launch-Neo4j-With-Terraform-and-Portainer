# Variables
variable "project_id" {
  description = "Unique identifier for the project"
  type        = string
  default     = "myneo4j"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m5.4xlarge"
}

variable "ami" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = "ami-08a0d1e16fc3f61ea"
}

variable "allowed_source_ips" {
  description = "List of IP addresses allowed to access the instance"
  type        = list(string)
  default     = []
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "http" "my_public_ip" {
  url = "https://api.ipify.org"
  request_headers = {
    Accept = "application/text"
  }
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_id}-main-vpc"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_id}-main-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_id}-public-subnet"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Route Table
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

# Route Table Association
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "allow_sources" {
  name        = "${var.project_id}_allow_sources"
  description = "Allow SSH and application inbound traffic"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH from allowed sources"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_source_ips) > 0 ? var.allowed_source_ips : ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  # Neo4j HTTP
  ingress {
    description = "Neo4j 7474"
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_source_ips) > 0 ? var.allowed_source_ips : ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  # Neo4j Bolt
  ingress {
    description = "Neo4j Bolt (7687)"
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_source_ips) > 0 ? var.allowed_source_ips : ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  # NeoDash
  ingress {
    description = "NeoDash (5005)"
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_source_ips) > 0 ? var.allowed_source_ips : ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  # Caddy range
  ingress {
    description = "Caddy main-range (6000-6999)"
    from_port   = 6000
    to_port     = 6999
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_source_ips) > 0 ? var.allowed_source_ips : ["${chomp(data.http.my_public_ip.response_body)}/32"]
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

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for EC2
resource "aws_iam_role" "dev_role" {
  name = "${var.project_id}_dev_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "lambda.amazonaws.com"]
        }
      }
    ]
  })

  tags = {
    Name      = "${var.project_id}_dev_role"
    CreatedBy = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Policy for EC2 role
resource "aws_iam_policy" "dev_role_policy" {
  name        = "${var.project_id}_dev_role_policy"
  description = "Policy for EC2 instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_id}/*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "dev_role_policy_attachment" {
  role       = aws_iam_role.dev_role.name
  policy_arn = aws_iam_policy.dev_role_policy.arn
}

# Instance Profile
resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.project_id}-instance-profile"
  role = aws_iam_role.dev_role.name

  tags = {
    Name      = "${var.project_id}-instance-profile"
    CreatedBy = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# S3 Bucket for data
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "${var.project_id}-data-${random_string.bucket_suffix.result}"

  tags = {
    Name      = "${var.project_id}-data-bucket"
    CreatedBy = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload EC2 setup script to S3
resource "aws_s3_object" "ec2_setup_script" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "ec2-setup.sh"
  source = "${path.module}/../ec2-setup/user-data.sh"
  etag   = filemd5("${path.module}/../ec2-setup/user-data.sh")

  tags = {
    Name      = "ec2-setup-script"
    CreatedBy = "terraform"
  }
}

# Module calls for zipping and uploading code
module "caddy_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "code"
  source_dir      = "./../caddy"
  output_filename = "caddy.zip"
}

module "scripts_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "code"
  source_dir      = "./../scripts"
  output_filename = "scripts.zip"
}

module "docker_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "code"
  source_dir      = "./../docker"
  output_filename = "docker.zip"
}

module "ec2-setup_zip_upload" {
  source          = "./modules/zip_and_upload_to_s3"
  bucket_name     = aws_s3_bucket.data_bucket.id
  folder_name     = "code"
  source_dir      = "./../ec2-setup"
  output_filename = "ec2-setup.zip"
}

# Generate SSH key pair using TLS provider
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    create_before_destroy = true
  }
}

# Create AWS key pair from generated public key
resource "aws_key_pair" "main_key" {
  key_name   = "${var.project_id}_key_pair"
  public_key = tls_private_key.this.public_key_openssh

  tags = {
    Name      = "${var.project_id}_key_pair"
    CreatedBy = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Save private key to local file (for development only)
resource "local_file" "private_key" {
  content  = tls_private_key.this.private_key_pem
  filename = "../keys/private_key.pem"
}

# Save public key to local file
resource "local_file" "public_key" {
  content  = tls_private_key.this.public_key_openssh
  filename = "../keys/public_key.pub"
}

# EC2 Instance
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
    export NEO4J_SECRET_ARN="${aws_secretsmanager_secret.neo4j_credentials.arn}"
    export JWT_SECRET_ARN="${aws_secretsmanager_secret.jwt_secret.arn}"
    export DATA_BUCKET_NAME="${aws_s3_bucket.data_bucket.id}"
    export PROJECT_ID="${var.project_id}"
    export AWS_REGION="${data.aws_region.current.name}"
    
    # Get Neo4j password from Secrets Manager
    export NEO4J_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $NEO4J_SECRET_ARN --query SecretString --output text | jq -r '.password')
    
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

# Elastic IP
resource "aws_eip" "dev_ec2_eip" {
  instance = aws_instance.main_instance.id
  tags = {
    Name      = "${var.project_id}_dev_ec2_eip"
    CreatedBy = "terraform"
  }
}