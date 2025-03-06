#!/bin/bash

# Ensure required variables are set
: "${SECRET_NAME:?}" "${CIRCLE_HOSTNAME:?}" "${CIRCLE_PROJECT_USERNAME:?}" "${CIRCLE_PROJECT_REPONAME:?}" "${CIRCLE_TOKEN:?}"

# Fetch the secret JSON from GCP
SECRET_JSON=$(gcloud secrets versions access latest --secret="$SECRET_NAME")

# Convert JSON into key-value pairs and iterate safely
jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$SECRET_JSON" | \
while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(tr '[:lower:]/.-' '[:upper:]___' <<< "$key")"
  export "$ENV_VAR_NAME=$value"

  # Post each secret to CircleCI as an environment variable and handle responses
  response_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --url "https://${CIRCLE_HOSTNAME}/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: ${CIRCLE_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}")

  if [ "$response_code" -eq 201 ]; then
    echo "Successfully set $ENV_VAR_NAME (Response: $response_code)"
  else
    echo "Failed to set $ENV_VAR_NAME, Response Code: $response_code" >&2
    # Retry command verbosely for debugging
    curl --request POST \
      --url "https://${CIRCLE_HOSTNAME}/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
      --header "Circle-Token: ${CIRCLE_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}"
  fi
done