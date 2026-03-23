#!/bin/bash

vllm bench serve \
  --backend openai-chat \
  --endpoint /v1/chat/completions \
  --model qwen35-35b \
  --tokenizer /data \
  --dataset-name random \
  --random-input-len 2048 \
  --random-output-len 512 \
  --num-prompts 3 \
  --request-rate 0.5