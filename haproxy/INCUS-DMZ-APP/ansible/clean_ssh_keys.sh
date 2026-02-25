#!/bin/bash

# Extract IPs from Terraform variables.tf using a simple grep/sed for convenience
# Alternatively, use 'terraform output' if the infrastructure is already applied
IPS=$(grep -oE '10\.0\.0\.[0-9]+' /home/mamat/terraform/terraform/pro/variables.tf | sort -u)

echo "Cleaning up known_hosts for the following IPs:"
for ip in $IPS; do
    echo "Processing $ip..."
    ssh-keygen -R "$ip" 2>/dev/null
done

echo "Done."
