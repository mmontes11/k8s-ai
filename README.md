# k8s-ai

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
- **Path**: `./infrastructure/llama-qwen35-35b`
- **Quantized**: `./infrastructure/llama-qwen35-35b-q3`
- **Description**: High-performance C/C++ inference engine
- **Features**:
  - Full precision (llama-qwen35-35b)
  - Quantized variant (llama-qwen35-35b-q3) for reduced memory footprint
  - 256k context window for agentic AI workflows
  - StatefulSet deployment with persistent storage
  - Prometheus ServiceMonitor integration

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
    ├── llama-qwen35-35b/   # Model deployments
    ├── huggingface/        # HF integration
    └── mcp-*/             # MCP server integrations
```

## License

[MIT](./LICENSE)
