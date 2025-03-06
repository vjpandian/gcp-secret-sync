#!/bin/bash
set -euo pipefail

# Ensure required commands are available
for cmd in curl jq gcloud; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# Extract hostname from CIRCLE_BUILD_URL and explicitly export it
if [ -z "${CIRCLE_HOSTNAME:-}" ]; then
  if [ -n "${CIRCLE_BUILD_URL:-}" ]; then
    temp=${CIRCLE_BUILD_URL#*://}       # Remove scheme (https://)
    CIRCLE_HOSTNAME=${temp%%/*}         # Extract hostname
    export CIRCLE_HOSTNAME

    if [ "$CIRCLE_HOSTNAME" = "circleci.com" ]; then
      echo -e "\033[1;32mCircleCI Cloud (circleci.com) detected!\033[0m"
    else
      echo -e "\033[1;33mServer install detected! Hostname: $CIRCLE_HOSTNAME\033[0m"
    fi
  else
    echo "ERROR: CIRCLE_BUILD_URL is not set; can't determine CIRCLE_HOSTNAME." >&2
    exit 1
  fi
fi

# Ensure required variables are set explicitly
: "${SECRET_NAME:?}" "${CIRCLE_HOSTNAME:?}" "${CIRCLE_PROJECT_USERNAME:?}" "${CIRCLE_PROJECT_REPONAME:?}" "${CIRCLE_TOKEN:?}"

# Fetch the secret JSON from GCP
SECRET_JSON=$(gcloud secrets versions access latest --secret="$SECRET_NAME")

# Convert JSON into key-value pairs and iterate safely (avoiding subshell issue)
while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(tr '[:lower:]/.-' '[:upper:]___' <<< "$key")"
  export "$ENV_VAR_NAME=$value"

  response_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --url "https://${CIRCLE_HOSTNAME}/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: ${CIRCLE_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}")

  if [ "$response_code" -eq 201 ]; then
    echo -e "\033[0;32mSuccessfully set $ENV_VAR_NAME (Response: $response_code)\033[0m"
  else
    echo -e "\033[0;31mFailed to set $ENV_VAR_NAME, Response Code: $response_code\033[0m" >&2
    # Retry verbosely for debugging
    curl --request POST \
      --url "https://${CIRCLE_HOSTNAME}/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
      --header "Circle-Token: ${CIRCLE_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}"
    exit 1
  fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$SECRET_JSON")