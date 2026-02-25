#!/bin/bash

# Server URL
URL="${1}"

# Test cases
declare -A tests

tests["SQL Injection"]="id=1' OR '1'='1"
tests["Cross Site Scripting (XSS)"]="<script>alert('xss')</script>"
tests["Local File Inclusion (LFI)"]="../../etc/passwd"
tests["Remote File Inclusion (RFI)"]="http://evil.com/shell.txt"
tests["Command Injection"]="; ls"

# Function to test a payload
test_payload() {
    local name=$1
    local payload=$2

    echo "Testing $name with payload: $payload"
    response=$(curl -s -o /dev/null -w "%{http_code}" "$URL" -d "$payload")
    
    if [ "$response" == "403" ]; then
        echo "PASS: $name blocked with status 403"
    else
        echo "FAIL: $name not blocked, status $response"
    fi
}

# Iterate over tests
for name in "${!tests[@]}"; do
    test_payload "$name" "${tests[$name]}"
done

