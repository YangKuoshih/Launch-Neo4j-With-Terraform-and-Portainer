# Store SSH private key in Secrets Manager
resource "aws_secretsmanager_secret" "ssh_private_key" {
  name        = "${var.project_id}-ssh-private-key"
  description = "SSH private key for EC2 instance access"
  
  tags = {
    Name      = "${var.project_id}-ssh-private-key"
    CreatedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = tls_private_key.this.private_key_pem
}