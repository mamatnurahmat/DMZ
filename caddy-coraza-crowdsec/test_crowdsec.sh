#!/bin/bash

# ============================================================
# Test CrowdSec Integration
# Usage: ./test_crowdsec.sh [URL]
# Default URL: http://whoami.local
#
# Prerequisites:
#   - docker compose up -d
#   - CrowdSec bouncer API key configured
# ============================================================

URL="${1:-http://whoami.local}"
COMPOSE_CMD="docker compose"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass=0
fail=0

check_http() {
    local desc="$1"
    local target_url="$2"
    local expected="$3"

    response=$(curl -s -o /dev/null -w "%{http_code}" "$target_url" 2>/dev/null)

    if [ "$response" == "$expected" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} $desc (HTTP $response)"
        ((pass++))
    else
        echo -e "  ${RED}✗ FAIL${NC} $desc (HTTP $response, expected $expected)"
        ((fail++))
    fi
}

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  CrowdSec Integration Test Suite${NC}"
echo -e "${YELLOW}  Target: ${URL}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

# --- Test 1: Normal access ---
echo -e "${CYAN}[1] Normal Access${NC}"
check_http "Normal request should return 200" "${URL}" "200"
echo ""

# --- Test 2: CrowdSec manual ban ---
echo -e "${CYAN}[2] CrowdSec Manual IP Ban${NC}"
MY_IP=$(curl -s -H "Host: whoami.local" "${URL}" 2>/dev/null | grep "RemoteAddr" | head -1 | awk -F: '{print $2}' | tr -d ' ')
if [ -z "$MY_IP" ]; then
    MY_IP="172.18.0.1"
fi
echo -e "  ${YELLOW}→ Detected IP: ${MY_IP}${NC}"

echo -e "  ${YELLOW}→ Banning IP for 2 minutes...${NC}"
$COMPOSE_CMD exec -T crowdsec cscli decisions add -i "$MY_IP" -d 2m -t ban 2>/dev/null
sleep 3

check_http "Banned IP should return 403" "${URL}" "403"
echo ""

# --- Test 3: CrowdSec unban ---
echo -e "${CYAN}[3] CrowdSec Unban${NC}"
echo -e "  ${YELLOW}→ Removing ban...${NC}"
$COMPOSE_CMD exec -T crowdsec cscli decisions delete --ip "$MY_IP" 2>/dev/null
sleep 3

check_http "Unbanned IP should return 200" "${URL}" "200"
echo ""

# --- Test 4: AppSec — sensitive paths ---
echo -e "${CYAN}[4] AppSec — Sensitive Path Detection${NC}"
check_http "Access /.env should be blocked" "${URL}/.env" "403"
check_http "Access /wp-admin should be blocked" "${URL}/wp-admin" "403"
check_http "Access /phpinfo.php should be blocked" "${URL}/phpinfo.php" "403"
check_http "Access /.git/config should be blocked" "${URL}/.git/config" "403"
echo ""

# --- Test 5: CrowdSec alerts ---
echo -e "${CYAN}[5] CrowdSec Alerts & Decisions${NC}"
echo -e "  ${YELLOW}→ Current alerts:${NC}"
$COMPOSE_CMD exec -T crowdsec cscli alerts list --limit 5 2>/dev/null | head -15
echo ""
echo -e "  ${YELLOW}→ Current decisions:${NC}"
$COMPOSE_CMD exec -T crowdsec cscli decisions list 2>/dev/null | head -10
echo ""

# --- Test 6: CrowdSec metrics ---
echo -e "${CYAN}[6] CrowdSec Metrics${NC}"
echo -e "  ${YELLOW}→ Acquisition metrics:${NC}"
$COMPOSE_CMD exec -T crowdsec cscli metrics show acquisition 2>/dev/null | head -15
echo ""

# --- Summary ---
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
total=$((pass + fail))
echo -e "  Results: ${GREEN}${pass} passed${NC} / ${RED}${fail} failed${NC} / ${total} total"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  docker compose exec crowdsec cscli alerts list"
echo "  docker compose exec crowdsec cscli decisions list"
echo "  docker compose exec crowdsec cscli decisions add -i <IP> -d 5m -t ban"
echo "  docker compose exec crowdsec cscli decisions delete --ip <IP>"
echo "  docker compose exec crowdsec cscli metrics show acquisition"
echo "  docker compose exec crowdsec cscli bouncers list"
