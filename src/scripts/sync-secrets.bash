#!/bin/bash

set -e  # Exit on error

SECRET_FILE="/tmp/secret.json"
RESPONSE_FILE="/tmp/circleci_response.log"

echo "🔄 Fetching secret from Google Cloud..."
if ! gcloud secrets versions access latest --secret="$SECRET_NAME" > "$SECRET_FILE" 2>/dev/null; then
  echo "❌ ERROR: Failed to fetch secret from GCP." >&2
  exit 1
fi
echo "✅ Successfully retrieved secret from GCP and saved to $SECRET_FILE."

# Validate JSON
echo "🔄 Validating secret JSON format..."
if ! jq empty "$SECRET_FILE" >/dev/null 2>&1; then
  echo "❌ ERROR: Retrieved secret is not valid JSON." >&2
  rm -f "$SECRET_FILE"  # Ensure file is deleted
  exit 1
fi
echo "✅ Secret JSON is valid."

# Process and upload each key-value pair with a 4-second delay between each request
echo "🔄 Setting environment variables in CircleCI..."
jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$SECRET_FILE" | while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(echo "$key" | tr '[:lower:]/.-' '[:upper:]___')"
  SAFE_VALUE="$(echo "$value" | tr -d '\n' | jq -Rr @json)"  # Remove newlines, escape JSON

  echo "📤 Sending request to CircleCI for $ENV_VAR_NAME..."
  curl --noproxy "*" --request POST \
    --url "https://circleci.com/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: $CIRCLE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":$SAFE_VALUE}" \
    --verbose > "$RESPONSE_FILE" 2>&1

  # Extract HTTP status code
  http_code=$(grep '< HTTP' "$RESPONSE_FILE" | tail -1 | awk '{print $3}')

  echo "🔍 HTTP Response Code: $http_code"
  echo "🔍 Full Response:"
  cat "$RESPONSE_FILE"

  if [ "$http_code" -eq 201 ]; then
    echo "✅ Successfully set $ENV_VAR_NAME"
  else
    echo "❌ ERROR: Failed to set $ENV_VAR_NAME. HTTP status: $http_code"
    rm -f "$SECRET_FILE" "$RESPONSE_FILE"  # Clean up before exiting
    exit 1
  fi

  # Introduce a 4-second delay to prevent rate-limiting issues
  echo "⏳ Waiting 4 seconds before the next request..."
  sleep 4
done

# Delete the secret file after successful execution
rm -f "$SECRET_FILE" "$RESPONSE_FILE"
echo "🧹 Successfully deleted temporary secret file and response log."
