#!/bin/bash
# Script to retrieve secrets from AWS Secrets Manager

PROJECT_ID=${PROJECT_ID:-myneo4j}
AWS_REGION=${AWS_REGION:-us-east-1}

# Get Neo4j credentials
NEO4J_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${PROJECT_ID}-neo4j-credentials" \
  --region "$AWS_REGION" \
  --query SecretString --output text)

export NEO4J_USERNAME=$(echo "$NEO4J_SECRET" | jq -r '.username')
export NEO4J_PASSWORD=$(echo "$NEO4J_SECRET" | jq -r '.password')

# Get JWT secret
JWT_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${PROJECT_ID}-jwt-secret" \
  --region "$AWS_REGION" \
  --query SecretString --output text)

export JWT_SECRET_KEY=$(echo "$JWT_SECRET" | jq -r '.jwt_secret_key')

echo "Secrets loaded into environment variables"
echo "NEO4J_USERNAME: $NEO4J_USERNAME"
echo "NEO4J_PASSWORD: [HIDDEN]"
echo "JWT_SECRET_KEY: [HIDDEN]"