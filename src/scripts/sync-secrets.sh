#!/bin/bash

set -eo pipefail  # Ensures the script exits on any error and catches pipeline failures

echo "🔍 Starting CircleCI Environment Variable Setup..."

# Step 1: Check for required dependencies
echo "🔄 Checking required dependencies..."
for cmd in curl jq gcloud; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done
echo "✅ All required dependencies are installed."

# Step 2: Ensure required environment variables are set
echo "🔄 Checking required environment variables..."
REQUIRED_VARS=("SECRET_NAME" "CIRCLE_TOKEN" "CIRCLE_PROJECT_USERNAME" "CIRCLE_PROJECT_REPONAME")

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: Required environment variable '$var' is not set." >&2
    exit 1
  fi
done
echo "✅ All required environment variables are set."

# Step 3: Validate and clean CircleCI API token
echo "🔄 Validating CircleCI API token..."

# Trim newlines from CIRCLE_TOKEN to prevent formatting issues
CIRCLE_TOKEN=$(echo "$CIRCLE_TOKEN" | tr -d '\n')

response=$(curl --silent --request GET \
  --url "https://circleci.com/api/v2/me" \
 