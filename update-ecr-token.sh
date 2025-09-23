#!/bin/bash

set -e

echo "Starting ECR token refresh..."

# Validate required environment variables
required_vars=(AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY INFISICAL_TOKEN INFISICAL_PROJECT_ID INFISICAL_ENV)

missing_vars=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    missing_vars+=("$var")
  fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
  echo "ERROR: Missing required environment variables:"
  for mv in "${missing_vars[@]}"; do
    echo "  - $mv"
  done
  exit 1
fi

# Set Infisical URL (default to cloud if not specified)
INFISICAL_URL="${INFISICAL_URL:-https://app.infisical.com}"
echo "Using Infisical URL: $INFISICAL_URL"

# Get ECR token
echo "Getting ECR token for region: $AWS_REGION"
ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")

if [ -z "$ECR_TOKEN" ]; then
    echo "ERROR: Failed to retrieve ECR token"
    exit 1
fi

echo "ECR token retrieved successfully"

# Update token in Infisical using CLI
echo "Updating ECR token in Infisical..."

# Set the secret using Infisical CLI with URL
if infisical secrets set ECR_TOKEN="$ECR_TOKEN" \
    --projectId="$INFISICAL_PROJECT_ID" \
    --env="$INFISICAL_ENV" \
    --token="$INFISICAL_TOKEN" \
    --domain="$INFISICAL_URL"; then
    echo "SUCCESS: ECR token updated in Infisical"
else
    echo "ERROR: Failed to update ECR token in Infisical"
    exit 1
fi

echo "ECR token refresh completed successfully"
