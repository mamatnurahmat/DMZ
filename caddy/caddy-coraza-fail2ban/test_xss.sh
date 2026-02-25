#!/bin/bash

# Server URL
URL="${1}"

curl -I "${URL}/?search=<script>alert('CRS+Sandbox+Release')</script>"
