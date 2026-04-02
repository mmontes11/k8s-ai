# 🧠 k8s-ai

Tenant repository bootstrapped by [k8s-infrastructure](https://github.com/mmontes11/k8s-infrastructure) that contains the manifests for AI related applications

## Overview

This repository manages AI workloads on Kubernetes using GitOps with Flux CD. It includes deployments for LLM inference services, web UIs, and model serving infrastructure.

## Applications

### Open WebUI
- **Path**: `./apps/open-webui`
- **Type**: HelmRelease (ollama-webui chart)
- **Description**: Web interface for interacting with LLMs
- **Features**: 
  - Persistent storage via PVC
  - Integration with Ollama backend
  - Model access control bypass enabled

### ComfyUI
- **Path**: `./apps/comfyui`
- **Type**: Native Kubernetes resources
- **Description**: Graph-based interface for Stable Diffusion
- **Features**:
  - Persistent volume for model caching
  - Replication source/destination for data synchronization
  - RESTic backup support

## Infrastructure

### Model Serving

#### Ollama
- **Path**: `./infrastructure/ollama`
- **Description**: Lightweight LLM inference server
- **Features**:
  - Native GPU support
  - Simple HTTP API
  - Model caching

#### llama.cpp
- **Path**: `./infrastructure/llamacpp`
- **Description**: High-performance C/C++ inference engine optimized for CPU and GPU
- **Features**:
  - Qwen3.5-35B model support with full precision
  - 256k context window for agentic AI workflows
  - StatefulSet deployment with persistent storage
  - Prometheus ServiceMonitor integration
  - Ingress routing via HTTPRoute

#### vLLM
- **Path**: `./infrastructure/vllm`
- **Description**: High-throughput LLM serving with PagedAttention
- **Use Case**: Production workloads requiring high concurrency

#### KServe
- **Path**: `./infrastructure/kserve`
- **Example**: `./examples/llminferenceservice.yaml`
- **Description**: Kubernetes-native ML serving platform
- **Features**:
  - LLMInferenceService CRD
  - Custom model templates

### MCP Servers
- **MCP Kubernetes**: Kubernetes model context protocol server
- **MCP Grafana**: Grafana monitoring integration
- **MCP GitHub**: GitHub API integration
- **MCP Photoprism**: Photo management (mmontes & xiaowen)

## Architecture

```
├── apps/                    # Application deployments
│   ├── comfyui/            # ComfyUI deployment
│   └── open-webui/         # Open WebUI deployment
├── clusters/               # Cluster-specific configurations
│   └── homelab/
│       ├── apps.yaml       # Application Kustomizations
│       ├── infrastructure.yaml
│       └── namespaces.yaml
├── examples/               # Example configurations
│   └── llminferenceservice.yaml
└── infrastructure/         # Shared infrastructure
    ├── kserve/             # KServe ML serving
    ├── vllm/               # vLLM serving engine
    ├── ollama/             # Ollama LLM backend
    ├── llamacpp/           # llama.cpp inference engine
    ├── workspace/          # OpenCode AI development workspace
    ├── huggingface/        # HF integration
    └── mcp-*/             # MCP server integrations
```

## AI Workspace

Development environment for AI workloads based on [docker-ai-workspace](https://github.com/mmontes11/docker-ai-workspace):

- **OpenCode instance** for interactive AI development
- **NVIDIA GPU support** for accelerated model training and inference
- Pre-configured for AI/ML development

## AI Benchmarks

LLM benchmarks using llama.cpp on Kubernetes: [mmontes11/llm-bench](https://github.com/mmontes11/llm-bench)

Key benchmarks (NVIDIA RTX PRO 4000 Blackwell, 23.5 GiB VRAM):
- **Qwen3.5-35B-A3B** (Q4_K_Medium): 2995 t/s @ 2048 prompts, 84.87 t/s token generation
- **GPT-OSS 20B** (MXFP4 MoE): 2704 t/s @ 2048 prompts, 109.68 t/s token generation

## License

[MIT](./LICENSE)
