# AWS Secrets Manager for sensitive configuration
resource "aws_secretsmanager_secret" "neo4j_credentials" {
  name        = "${var.project_id}-neo4j-credentials-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  description = "Neo4j database credentials"
  
  tags = {
    Name      = "${var.project_id}-neo4j-credentials"
    CreatedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "neo4j_credentials" {
  secret_id = aws_secretsmanager_secret.neo4j_credentials.id
  secret_string = jsonencode({
    username = "neo4j"
    password = random_password.neo4j_password.result
  })
}

resource "random_password" "neo4j_password" {
  length  = 16
  special = true
}

# JWT Secret in Secrets Manager
resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project_id}-jwt-secret-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  description = "JWT secret key for controller authentication"
  
  tags = {
    Name      = "${var.project_id}-jwt-secret"
    CreatedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id = aws_secretsmanager_secret.jwt_secret.id
  secret_string = jsonencode({
    jwt_secret_key = random_string.controller_jwt_secret_key.result
  })
}

# Update IAM policy to allow access to secrets
resource "aws_iam_policy" "secrets_access" {
  name        = "${var.project_id}-secrets-access"
  description = "Allow access to secrets manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.neo4j_credentials.arn,
          aws_secretsmanager_secret.jwt_secret.arn,
          aws_secretsmanager_secret.ssh_private_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.dev_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}