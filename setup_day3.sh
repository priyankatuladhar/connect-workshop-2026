cat << 'EOF' > setup_day3.sh
#!/bin/bash
set -e

# ==========================================
# 0. SET YOUR VARIABLES HERE
# ==========================================
PARTICIPANT="yourname"
REGION="us-east-1"
KEY_ARN="your-kms-key-arn"

REPO_URL="https://github.com/priyankatuladhar/connect-workshop-2026.git"
REPO_DIR="connect-workshop-2026"

echo "=== STARTING DAY 3 AUTOMATED SETUP ==="
echo "Participant: $PARTICIPANT"
echo "Region:      $REGION"
echo "KMS Key:     $KEY_ARN"
echo "--------------------------------------"

# ==========================================
# 1. VERIFY DAY 1 STACK
# ==========================================
echo "1. Checking Day 1 Stack..."
DAY1_STATUS=$(aws cloudformation describe-stacks \
  --stack-name nmc-${PARTICIPANT}-day1 \
  --region ${REGION} \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DAY1_STATUS" != "CREATE_COMPLETE" ]; then
  echo "❌ ERROR: Day 1 stack (nmc-${PARTICIPANT}-day1) is not in CREATE_COMPLETE status (Status: $DAY1_STATUS)."
  echo "Please deploy day1-foundation.yaml first."
  exit 1
fi
echo "✓ Day 1 stack verified (CREATE_COMPLETE)"

# ==========================================
# 2. CLONE REPOSITORY
# ==========================================
echo "2. Fetching workshop repository..."
if [ -d "$REPO_DIR" ]; then
  echo "  Repository directory exists, pulling latest..."
  cd "$REPO_DIR" && git pull && cd ..
else
  git clone "$REPO_URL"
fi

# ==========================================
# 3. DEPLOY DAY 3 STACK
# ==========================================
echo "3. Deploying Day 3 Stack (Lambda Functions)..."
aws cloudformation deploy \
  --template-file ${REPO_DIR}/day3-lambda.yaml \
  --stack-name nmc-${PARTICIPANT}-day3 \
  --parameter-overrides \
    ParticipantName=${PARTICIPANT} \
    KmsKeyArn=${KEY_ARN} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION}

aws cloudformation wait stack-create-complete \
  --stack-name nmc-${PARTICIPANT}-day3 \
  --region ${REGION}
echo "✓ Day 3 stack ready"

# ==========================================
# 4. UPLOAD LAMBDA CODE
# ==========================================
echo "4. Staging and uploading Lambda function zip packages..."
cp ~/${REPO_DIR}/lambda/zips/*.zip ~/

for fn in verify-identity check-available-slots book-appointment \
          reschedule-appointment cancel-appointment lookup-appointment \
          request-prescription-refill log-call-result customer-lookup \
          update-q-session sample-data-seeder api-key-retrieval; do
  echo -n "  Uploading $fn... "
  aws lambda update-function-code \
    --function-name nmc-${PARTICIPANT}-${fn} \
    --zip-file fileb://~/${fn}.zip \
    --region ${REGION} \
    --query 'FunctionName' \
    --output text
done
echo "✓ All 12 Lambda functions updated"

# ==========================================
# 5. DEPLOY DAY 4 STACK
# ==========================================
echo "5. Deploying Day 4 Stack (API Gateway)..."
aws cloudformation deploy \
  --template-file ${REPO_DIR}/day4-apigateway.yaml \
  --stack-name nmc-${PARTICIPANT}-day4 \
  --parameter-overrides \
    ParticipantName=${PARTICIPANT} \
  --region ${REGION}

aws cloudformation wait stack-create-complete \
  --stack-name nmc-${PARTICIPANT}-day4 \
  --region ${REGION}
echo "✓ Day 4 stack ready"

API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name nmc-${PARTICIPANT}-day4 \
  --region ${REGION} \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text)

# ==========================================
# 6. DEPLOY DAY 5 STACK
# ==========================================
echo "6. Deploying Day 5 Stack (Sample Data)..."
aws cloudformation deploy \
  --template-file ${REPO_DIR}/day5-data.yaml \
  --stack-name nmc-${PARTICIPANT}-day5 \
  --parameter-overrides \
    ParticipantName=${PARTICIPANT} \
  --region ${REGION}

aws cloudformation wait stack-create-complete \
  --stack-name nmc-${PARTICIPANT}-day5 \
  --region ${REGION}
echo "✓ Day 5 stack ready"

API_KEY=$(aws cloudformation describe-stacks \
  --stack-name nmc-${PARTICIPANT}-day5 \
  --region ${REGION} \
  --query "Stacks[0].Outputs[?OutputKey=='ApiKeyValue'].OutputValue" \
  --output text)

# ==========================================
# 7. SMOKE TEST
# ==========================================
echo "7. Running smoke tests..."
TEST_VERIFY=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_ENDPOINT}/tools/verify-identity" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d '{"phoneNumber":"+16505551001","dateOfBirth":"1985-03-15"}')

if [ "$TEST_VERIFY" -eq 200 ]; then
  echo "✓ Smoke test passed! (HTTP 200)"
else
  echo "⚠️ Warning: Smoke test returned HTTP status $TEST_VERIFY"
fi

# ==========================================
# 8. OUTPUT SUMMARY
# ==========================================
echo ""
echo "=================================================="
echo "🎉 SETUP COMPLETE - SAVE THESE VALUES FOR DAY 3:"
echo "=================================================="
echo "Participant:   $PARTICIPANT"
echo "Region:        $REGION"
echo "API Endpoint:  $API_ENDPOINT"
echo "API Key:       $API_KEY"
echo "=================================================="

EOF

chmod +x setup_day3.sh
./setup_day3.sh