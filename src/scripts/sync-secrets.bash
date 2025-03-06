#!/bin/bash
set -e  # Exit on error

SECRET_FILE="/tmp/secret.json"
RESPONSE_FILE="/tmp/circleci_response.log"

fetch_secret() {
  echo "Fetching secret from Google Cloud..."
  if ! gcloud secrets versions access latest --secret="$SECRET_NAME" > "$SECRET_FILE" 2>/dev/null; then
    echo "ERROR: Failed to fetch secret from GCP." >&2
    exit 1
  fi
  echo "Successfully retrieved secret from GCP."
}

validate_json() {
  echo "Validating secret JSON format..."
  if ! jq empty "$SECRET_FILE" >/dev/null 2>&1; then
    echo "ERROR: Retrieved secret is not valid JSON." >&2
    cleanup
    exit 1
  fi
  echo "Secret JSON is valid."
}

set_circleci_env_vars() {
  echo "Setting environment variables in CircleCI..."
  jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$SECRET_FILE" | while IFS=$'\t' read -r key value; do
    ENV_VAR_NAME="ENV_VAR_$(echo "$key" | tr '[:lower:]/.-' '[:upper:]___')"
    SAFE_VALUE=$(echo "$value" | tr -d '\n' | jq -Rr @json)  # Remove newlines, escape JSON

    echo "Sending request to CircleCI for $ENV_VAR_NAME..."
    http_code=$(curl --noproxy "*" --silent --show-error --request POST \
      --url "https://circleci.com/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
      --header "Circle-Token: $CIRCLE_TOKEN" \
      --header 'Content-Type: application/json' \
      --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":$SAFE_VALUE}" \
      --output /dev/null --write-out "%{http_code}")

    if [[ "$http_code" -eq 201 ]]; then
      echo "Successfully set $ENV_VAR_NAME"
    else
      echo "ERROR: Failed to set $ENV_VAR_NAME. HTTP status: $http_code" >&2
      cleanup
      exit 1
    fi

  done
}

cleanup() {
  rm -f "$SECRET_FILE" "$RESPONSE_FILE"
  echo "Cleanup completed."
}

# Execution flow
fetch_secret
validate_json
set_circleci_env_vars
cleanup

echo ""
echo ""
echo "These values fetched from GCP secrets manager should be masked now....."
echo $ENV_VAR_API_KEY
echo $ENV_VAR_DB_PASSWORD