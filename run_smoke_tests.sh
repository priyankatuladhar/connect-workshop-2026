cat << 'EOF' > run_smoke_tests.sh
#!/bin/bash

# Ensure required environment variables are present
if [ -z "$API_ENDPOINT" ] || [ -z "$API_KEY" ]; then
  echo "❌ Error: \$API_ENDPOINT or \$API_KEY is not set."
  echo "Please set them or run your variable reset block first."
  exit 1
fi

echo "=================================================="
echo "🚀 RUNNING BACKEND SMOKE TESTS"
echo "Endpoint: $API_ENDPOINT"
echo "=================================================="
echo ""

# Helper function to invoke endpoints
test_endpoint() {
  local name="$1"
  local path="$2"
  local payload="$3"

  echo "--------------------------------------------------"
  echo "🧪 Testing: $name"
  echo "POST ${API_ENDPOINT}${path}"
  echo "--------------------------------------------------"

  response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${API_ENDPOINT}${path}" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -d "$payload")

  http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
  body=$(echo "$response" | sed '/HTTP_STATUS/d')

  if [ "$http_status" -eq 200 ]; then
    echo -e "Status: \033[0;32m$http_status OK\033[0m"
    echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
  else
    echo -e "Status: \033[0;31m$http_status FAILED\033[0m"
    echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
  fi
  echo ""
}

# 1. Verify Identity
test_endpoint "Verify Identity" "/tools/verify-identity" \
  '{"phoneNumber":"+16505551001","dateOfBirth":"1985-03-15"}'

# 2. Customer Lookup
test_endpoint "Customer Lookup" "/tools/customer-lookup" \
  '{"phoneNumber":"+16505551001"}'

# 3. Check Available Slots
test_endpoint "Check Available Slots" "/tools/check-available-slots" \
  '{"specialty":"General Practice","numberOfDays":7}'

# 4. Lookup Appointment
test_endpoint "Lookup Appointment" "/tools/lookup-appointment" \
  '{"patientId":"P-1001"}'

# 5. Book Appointment
test_endpoint "Book Appointment" "/tools/book-appointment" \
  '{"patientId":"P-1001","slotId":"S-2001","reason":"Annual Checkup"}'

# 6. Reschedule Appointment
test_endpoint "Reschedule Appointment" "/tools/reschedule-appointment" \
  '{"appointmentId":"A-3001","newSlotId":"S-2002"}'

# 7. Request Prescription Refill
test_endpoint "Request Prescription Refill" "/tools/request-prescription-refill" \
  '{"patientId":"P-1001","medicationName":"Amoxicillin","pharmacyDetails":"Main St Pharmacy"}'

# 8. Log Call Result
test_endpoint "Log Call Result" "/tools/log-call-result" \
  '{"patientId":"P-1001","callType":"Inbound","summary":"Patient inquired about slot availability.","disposition":"Resolved"}'

echo "=================================================="
echo "✅ SMOKE TESTS COMPLETE"
echo "=================================================="
EOF

chmod +x run_smoke_tests.sh
./run_smoke_tests.sh