curl -sS -X POST https://facebook-test.mmontes-internal.duckdns.org/v1/completions   \
    -H 'accept: application/json'   \
    -H 'Content-Type: application/json'    \
    -d '{
        "model": "facebook/opt-125m",
        "prompt":"Who let the dogs out?"
      }' | jq

curl -sS -X POST http://localhost:8000/v1/completions   \
    -H 'accept: application/json'   \
    -H 'Content-Type: application/json'    \
    -d '{
        "model": "facebook/opt-125m",
        "prompt":"Who let the dogs out?"
      }' | jq