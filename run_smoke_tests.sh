#!/bin/bash
# Runs smoke tests against all 8 API endpoints.
# Requires $API_ENDPOINT and $API_KEY to be set.
#
# Usage:
#   bash run_smoke_tests.sh
#
# Or inline:
#   API_ENDPOINT="https://..." API_KEY="abc123" bash run_smoke_tests.sh

set -e

if [ -z "$API_ENDPOINT" ] || [ -z "$API_KEY" ]; then
  echo "ERROR: \$API_ENDPOINT and \$API_KEY must be set before running this script."
  echo ""
  echo "Run the variable reset block from setup_day3.sh first, or export them:"
  echo "  export API_ENDPOINT=\"https://xxxxxxxxxx.execute-api.REGION.amazonaws.com/prod\""
  echo "  export API_KEY=\"your-api-key-value\""
  exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

hr() { echo -e "${CYAN}────────────────────────────────────────────────────────${RESET}"; }

PASS=0
FAIL=0

test_endpoint() {
  local name="$1"
  local path="$2"
  local payload="$3"

  echo ""
  echo -e "${BOLD}Testing: ${name}${RESET}"
  echo "  POST ${API_ENDPOINT}${path}"

  response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "${API_ENDPOINT}${path}" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -d "$payload")

  http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
  body=$(echo "$response" | sed '/HTTP_STATUS/d')

  if [ "$http_status" = "200" ]; then
    echo -e "  Status: ${GREEN}${http_status} OK${RESET}"
    echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
    PASS=$((PASS + 1))
  else
    echo -e "  Status: ${RED}${http_status} FAILED${RESET}"
    echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
    FAIL=$((FAIL + 1))
  fi
}

hr
echo -e "${BOLD}  Nepal Medical Care — Backend Smoke Tests${RESET}"
echo "  Endpoint: ${API_ENDPOINT}"
hr

test_endpoint "1. Verify Identity" "/tools/verify-identity" \
  '{"phoneNumber":"+16505551001","dateOfBirth":"1985-03-15"}'

test_endpoint "2. Customer Lookup" "/tools/customer-lookup" \
  '{"phoneNumber":"+16505551001"}'

test_endpoint "3. Check Available Slots" "/tools/check-available-slots" \
  '{"specialty":"General Practice","numberOfDays":7}'

test_endpoint "4. Lookup Appointment" "/tools/lookup-appointment" \
  '{"patientId":"P-1001"}'

test_endpoint "5. Book Appointment" "/tools/book-appointment" \
  '{"patientId":"P-1001","slotId":"S-2001","reason":"Annual Checkup"}'

test_endpoint "6. Reschedule Appointment" "/tools/reschedule-appointment" \
  '{"appointmentId":"A-3001","newSlotId":"S-2002"}'

test_endpoint "7. Request Prescription Refill" "/tools/request-prescription-refill" \
  '{"patientId":"P-1001","medicationName":"Amoxicillin","pharmacyDetails":"Main St Pharmacy"}'

test_endpoint "8. Log Call Result" "/tools/log-call-result" \
  '{"patientId":"P-1001","callType":"Inbound","summary":"Patient inquired about slot availability.","disposition":"Resolved"}'

echo ""
hr
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}All ${PASS} tests passed.${RESET}"
else
  echo -e "  ${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET}"
  echo ""
  echo "  If you see 501: Lambda code not uploaded — run setup_day3.sh again"
  echo "  If you see 403: API key is wrong — re-export \$API_KEY"
fi
hr
echo ""
