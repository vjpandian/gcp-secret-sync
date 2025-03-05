#!/bin/bash
# This example uses envsubst to support variable substitution in the string parameter type.
# https://circleci.com/docs/orbs-best-practices/#accepting-parameters-as-strings-or-environment-variables
SECRET_JSON=$(gcloud secrets versions access latest --secret=$SECRET_NAME)
            
# First loop: Export and post each key-value pair to CircleCI
keys_and_values=$(echo "$SECRET_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')

echo "$keys_and_values" | while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(echo $key | tr '[:lower:]/.-' '[:upper:]___')"
  export $ENV_VAR_NAME="$value"

  # Post each secret to CircleCI as an environment variable and handle responses
  response_code=$(curl --silent --output /dev/null --write-out "%{http_code}" --request POST \
    --url "https://$CIRCLE_HOSTNAME/api/v2/project/gh/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/envvar" \
    --header "Circle-Token: $CIRCLE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}")

  if [ "$response_code" -eq 201 ]; then
    echo "Successfully set $ENV_VAR_NAME (Response: $response_code)"
  else
    echo "Failed to set $ENV_VAR_NAME, Response Code: $response_code"
    # Retry command verbosely for debugging
    curl --request POST \
      --url "https://circleci.com/api/v2/project/gh/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/envvar" \
      --header "Circle-Token: $CIRCLE_TOKEN" \
      --header 'Content-Type: application/json' \
      --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":\"$value\"}"
  fi
done