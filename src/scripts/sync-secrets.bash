
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

echo "🔄 Validating CircleCI API token with full verbosity..."

# Run verbose API request and store output
response=$(curl -vvv --request GET \
  --url "https://circleci.com/api/v2/me" \
  --header "Circle-Token: $CIRCLE_TOKEN" 2>&1)

# Print the full response (for debugging)
echo "🔍 DEBUG: Full Response:"

# Check if the response contains "200"
if echo "$response" | grep -q "200"; then
  echo "✅ CircleCI API token is valid (200 OK detected in verbose response)"
else
  echo "❌ ERROR: Token validation failed! '200' not found in response"
  exit 1
fi

# Step 4: Fetch secret from GCP
echo "🔄 Fetching secret from Google Cloud..."
SECRET_JSON="$(gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null)" || {
  echo "❌ ERROR: Failed to fetch secret from GCP." >&2
  exit 1
}
echo "✅ Successfully retrieved secret from GCP."
echo "$SECRET_JSON"

# Step 5: Validate JSON format
echo "🔄 Validating secret JSON format..."
if ! echo "$SECRET_JSON" | jq empty >/dev/null 2>&1; then
  echo "❌ ERROR: Retrieved secret is not valid JSON." >&2
  exit 1
fi
echo "✅ Secret JSON is valid."

# Step 6: Process JSON and set environment variables in CircleCI
echo "🔄 Setting environment variables in CircleCI..."
echo "$SECRET_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(echo "$key" | tr '[:lower:]/.-' '[:upper:]___')"
  SAFE_VALUE="$(echo "$value" | jq -sRr @json)"  # Escape special characters

  http_code=$(curl --silent --write-out "%{http_code}" --output /dev/null \
    --request POST \
    --url "https://circleci.com/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: $CIRCLE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":$SAFE_VALUE}")

  if [ "$http_code" -eq 201 ]; then
    echo "✅ Successfully set $ENV_VAR_NAME"
  else
    echo "❌ ERROR: Failed to set $ENV_VAR_NAME. HTTP status: $http_code"
    exit 1
  fi
done

echo "🎉✅ All environment variables have been set successfully in CircleCI!"
