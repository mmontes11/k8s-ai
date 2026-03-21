#!/bin/bash

curl -sS -X POST https://facebook-opt.mmontes-internal.duckdns.org/v1/completions   \
  -H 'accept: application/json'   \
  -H 'Content-Type: application/json'    \
  -d '{
      "model": "facebook/opt-125m",
      "prompt":"Who let the dogs out?"
    }' | jq