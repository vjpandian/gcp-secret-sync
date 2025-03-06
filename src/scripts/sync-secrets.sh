echo "🔍 Starting CircleCI Environment Variable Setup..."

# Step 1: Check for required dependencies
echo "🔄 Checking required dependencies..."
for cmd in curl jq gcloud; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done
echo "✅ All required dependencies are installed."

# Step 2: Ensure required environment variables are set
echo "🔄 Checking required environment variables..."
REQUIRED_VARS=("SECRET_NAME" "CIRCLE_TOKEN" "CIRCLE_PROJECT_USERNAME" "CIRCLE_PROJECT_REPONAME")
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ ERROR: Required environment variable '$var' is not set." >&2
    exit 1
  fi
done
echo "✅ All required environment variables are set."

# Step 3: Validate CircleCI API token correctly
echo "🔄 Validating CircleCI API token..."
response_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -X GET "https://circleci.com/api/v2/me" \
  --header "Circle-Token: ${CIRCLE_TOKEN}")

if [[ "$response_code" -eq 200 ]]; then
  echo "✅ CircleCI API token is valid."
else
  echo "❌ ERROR: Invalid CircleCI API token or insufficient permissions (Response: $response_code)" >&2
  exit 1
fi

# Step 4: Fetch secret from GCP
echo "🔄 Fetching secret from Google Cloud..."
SECRET_JSON=$(gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null) || {
  echo "❌ ERROR: Failed to fetch secret from GCP." >&2
  exit 1
}
echo "✅ Successfully retrieved secret from GCP."

# Step 5: Validate JSON format
echo "🔄 Validating secret JSON format..."
if ! jq empty <<< "$SECRET_JSON" 2>/dev/null; then
  echo "❌ ERROR: Retrieved secret is not valid JSON." >&2
  exit 1
fi
echo "✅ Secret JSON is valid."

# Step 6: Process JSON and set environment variables in CircleCI
echo "🔄 Setting environment variables in CircleCI..."
while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(tr '[:lower:]/.-' '[:upper:]___' <<< "$key")"
  SAFE_VALUE=$(echo "$value" | jq -sRr @json)  # Escape special characters

  response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    --url "https://circleci.com/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: ${CIRCLE_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":$SAFE_VALUE}")

  if [[ "$response_code" -eq 201 ]]; then
    echo "✅ Successfully set $ENV_VAR_NAME"
  else
    echo "❌ ERROR: Failed to set $ENV_VAR_NAME (Response: $response_code)" >&2
    exit 1
  fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$SECRET_JSON")

echo "🎉✅ All environment variables have been set successfully in CircleCI!"
