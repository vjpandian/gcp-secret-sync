
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
REQUIRED_VARS="SECRET_NAME CIRCLE_TOKEN CIRCLE_PROJECT_USERNAME CIRCLE_PROJECT_REPONAME"

for var in $REQUIRED_VARS; do
  eval "value=\${$var}"
  if [ -z "$value" ]; then
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
  --header "Circle-Token: $CIRCLE_TOKEN")

if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
  echo "✅ CircleCI API token is valid."
else
  echo "❌ ERROR: Invalid CircleCI API token or insufficient permissions."
  echo "🔍 Response: $response"
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
if ! echo "$SECRET_JSON" | jq empty >/dev/null 2>&1; then
  echo "❌ ERROR: Retrieved secret is not valid JSON." >&2
  exit 1
fi
echo "✅ Secret JSON is valid."

# Step 6: Process JSON and set environment variables in CircleCI
echo "🔄 Setting environment variables in CircleCI..."
echo "$SECRET_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key value; do
  ENV_VAR_NAME="ENV_VAR_$(echo "$key" | tr '[:lower:]/.-' '[:upper:]___')"
  SAFE_VALUE=$(echo "$value" | jq -sRr @json)  # Escape special characters

  response=$(curl --silent --request POST \
    --url "https://circleci.com/api/v2/project/gh/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/envvar" \
    --header "Circle-Token: $CIRCLE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$ENV_VAR_NAME\",\"value\":$SAFE_VALUE}\"")

  if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
    echo "✅ Successfully set $ENV_VAR_NAME"
  else
    echo "❌ ERROR: Failed to set $ENV_VAR_NAME"
    echo "🔍 Response: $response"
    exit 1
  fi
done

echo "🎉✅ All environment variables have been set successfully in CircleCI!"
