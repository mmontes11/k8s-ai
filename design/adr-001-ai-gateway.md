---
title: "ADR-0001: AI Gateway Adoption for the ai Tenant"
status: "Proposed"
date: "2026-10-30"
authors: "mmontes"
tags: ["architecture", "decision", "ai-gateway", "gateway-api", "observability"]
supersedes: ""
superseded_by: ""
---

# ADR-0001: AI Gateway Adoption for the ai Tenant

## Status

**Proposed**

## Context

The `ai` tenant of the homelab cluster (Flux CD GitOps on Talos) currently serves LLM inference through two independent stacks, each with its own entrypoint:

- **llama.cpp** (`infrastructure/llamacpp/`): StatefulSet in server mode with a 256k context, GPU-accelerated, and `--sleep-idle-seconds 3600` to conserve power. The `--metrics` flag is **disabled** (`infrastructure/llamacpp/llamacpp-statefulset.yaml:98-100`) because a Prometheus scrape wakes the sleeping model ([ggml-org/llama.cpp#20227](https://github.com/ggml-org/llama.cpp/issues/20227)). llama.cpp traffic therefore has no request-level observability at all.
- **vLLM** (via KServe): currently deployed through KServe's `LLMInferenceService` (`infrastructure/kserve/models/qwen38-27b-nvfp4-llminferenceservice.yaml`) — unsloth/Qwen3.8-27B-NVFP4 with 20.32 Gi of weights on a 23.42 Gi card (`--gpu-memory-utilization=0.92`, FP8 KV cache, `--max-num-seqs=1`, 20k context), routed by an `HTTPRoute` to Traefik. An alternative `vllm-stack` chart deployment (`infrastructure/vllm/`) exists but is **commented out** in `clusters/homelab/infrastructure.yaml` (CUDA OOM with Qwen3.5-35B-A3B-NVFP4). The engine exposes Prometheus metrics (ServiceMonitor exists), but only for this one stack.
- **Gateway API**: cluster ingress is provided by Traefik, which **does not implement** `InferencePool` from the Gateway API Inference Extension (GAIE), so model-aware routing is not available.

Applications (opencode, Open WebUI, n8n, MCP clients) each configure engine-specific endpoints. There is no unified OpenAI-compatible entrypoint, no auth/quotas at the edge, no failover between models, and no inference-level metrics (TTFT, TPOT, throughput) to base LLM inference optimization (see the [Modular handbook](https://handbook.modular.com/inference-optimization/)) on.

### Requirements

- **R1 — Unified entrypoint**: a single OpenAI-compatible endpoint routing to llama.cpp, vLLM, and (future) hosted providers, so clients stop configuring per-engine endpoints.
- **R2 — GAIE (hard requirement)**: the gateway must implement the [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/): `InferencePool` usable as an HTTPRoute backend with an endpoint picker.
- **R3 — Metrics + Grafana**: Prometheus-format LLM inference metrics aligned with the [Modular handbook](https://handbook.modular.com/llm-inference-basics/llm-inference-metrics/) — time-to-first-token (TTFT), time-per-output-token (TPOT), inter-chunk latency (ITL), end-to-end request duration, and token usage/throughput — plus importable Grafana dashboards. Metrics must work for llama.cpp traffic even though the engine's own metrics are disabled (the gap at `llamacpp-statefulset.yaml:98-100`), i.e. they must be measured per request, gateway-side.
- **R4 — Homelab fit**: single GPU (RTX PRO 4000 Blackwell, 24 GB, not MIG-capable). A larger/second GPU is under consideration but **not yet decided**. Prefill/decode disaggregation is not feasible until it lands. Low operational overhead, deployable through Flux, and the choice must stay reasonable both if that hardware never arrives and if it does.
- **R5 — Extra benefits**: auth, guardrails, failover, multi-provider, MCP/A2A, quotas, usage attribution.

### Constraint: Gateway API implementation

Because Traefik does not implement `InferencePool`, adopting GAIE requires an Envoy-family Gateway API implementation inside the `ai` tenant. This ADR therefore decides both the AI gateway and the underlying Gateway API implementation for the tenant.

## Candidates

All versions verified October 2026.

### Agent Router (formerly Envoy AI Gateway) — v1.2.0

[theagentrouter/agent-router](https://github.com/theagentrouter/agent-router) — Agentic AI Foundation (LF Projects) project, Apache 2.0, built on Envoy + Envoy Gateway (v1.9.2) with GAIE v1.6.2.

**PROs**

- Production-grade GAIE: `InferencePool` as an HTTPRoute backend with an endpoint picker (its "Tier Two" gateway), GAIE v1.6.2 — the reference deployment of the extension.
- `gen_ai.*` Prometheus metrics **on by default** (OpenTelemetry GenAI semantic conventions): token usage, TTFT, TPOT, request duration — a direct mapping of the Modular handbook metrics.
- Ships an importable Grafana dashboard: TTFT and request-duration percentiles, token usage by type, QPS, error/success rate by model.
- Purpose-built for AI: one OpenAI-compatible API across 20+ hosted providers and self-hosted engines; auth (API key / OIDC / JWT), quotas and rate limits, model failover, A/B routing, MCP server gateway, usage attribution.
- Tier One / Tier Two pattern fits the tenant: Tier One for edge ingress and global policy, Tier Two in front of the self-hosted inference cluster.
- Stable API surface: the rename from Envoy AI Gateway preserved CRDs, API group (`aigateway.envoyproxy.io`), CLI (`aigw`), images and Helm charts.

**CONs**

- Requires Envoy Gateway as the Gateway API implementation, so Traefik is displaced for `ai` traffic — a new Envoy control plane to operate.
- Young project (v1.x line, renamed/moved repos in 2026) — some link and doc churn; community smaller than Envoy Gateway or Istio.
- Gateway metrics are request-level; backend engine telemetry (vLLM, and llama.cpp while sleeping) still depends on the engines' own metrics. vLLM already has ServiceMonitors; the llama.cpp engine-level gap remains until [ggml-org/llama.cpp#20227](https://github.com/ggml-org/llama.cpp/issues/20227) lands, but is compensated gateway-side.

### agentgateway — v1.7.0

[agentgateway/agentgateway](https://github.com/agentgateway/agentgateway) — Linux Foundation project; Rust data plane with a Go controller.

**PROs**

- GAIE implemented: `InferencePool` backend support across the codebase (controller + data plane).
- Strong LLM metrics naming fidelity to the handbook: `agentgateway_gen_ai_server_time_to_first_token`, `time_per_output_token`, `inter_chunk_latency` (ITL), `request_duration`, `client_token_usage`, plus `agentgateway_gen_ai_client_cost_usd_total` (per-request cost tracking) and guardrail counters.
- Grafana dashboard shipped (`controller/install/dashboards/`) plus a Datadog example; LLM, MCP and A2A traffic in one data plane; high-performance Rust data plane.

**CONs**

- Configuration-first model (agentgateway config / CRDs) with Gateway API support via a syncer — less idiomatic for a Gateway-API-native GitOps tenant than the Envoy-family options.
- Younger and smaller ecosystem than the Envoy family; the Rust data plane is a less familiar debugging surface for the operator.
- Its GAIE/InferencePool support is newer, with fewer published production references than Agent Router's.

### llm-d — v1.0.0

[llm-d/llm-d](https://github.com/llm-d/llm-d) — CNCF sandbox project; a full LLM serving platform (router/EPP, model-server optimization, batch, async) built around GAIE.

**PROs**

- GAIE v1.6.2 with the reference EPP and router; InferencePool is first-class.
- The most complete observability story of the four: PodMonitor/ServiceMonitor recipes, 13 prebuilt Grafana dashboards (vLLM/SGLang overview, router/EPP, KV cache, P/D, batch), full metric reference docs, and per-token cost tracking via OpenCost. The EPP (an extension of the GAIE reference EPP) additionally exports `llm_d_epp_*` metrics: TTFT/TPOT/ITL/NTPOT per model *and priority/flow*, KV-cache utilization and queue depth per endpoint, prefix-indexer hit ratios, flow-control saturation, and SLO-violation counters.
- Strong serving roadmap: KV-cache-aware scheduling, batch gateway, multi-tenant QoS.

**CONs**

- It is a full serving platform, not just a gateway: it brings its own model-server orchestration (prefill/decode disaggregation, KV cache management) designed for multi-GPU/multi-node fleets — large overkill for a single 24 GB GPU, where P/D is not feasible until a second GPU lands (and that GPU is not yet decided).
- Its routing intelligence degenerates at current scale: with one endpoint per pool, the EPP scheduler has a single candidate — KV-cache-affinity routing, per-endpoint load balancing, flow control and SLO-aware scheduling all reduce to "forward to the only pod," so most of the EPP's extra metrics would be flat lines.
- Requires a separate Gateway API implementation (Istio 1.29.4 or Envoy Gateway) **in addition to** its router/EPP and monitoring components — the largest control-plane footprint of the four.
- Guides and recipes are GKE-centric; the operational burden (many operators, recipe namespaces) is the highest of the candidates.

### kgateway — v2.4.7

[kgateway-dev/kgateway](https://github.com/kgateway-dev/kgateway) — CNCF project (Solo.io); mature production Gateway API implementation.

**PROs**

- Mature, production-grade, highly conformant Gateway API implementation — a credible long-term general-purpose ingress (and a future Traefik replacement) for the cluster.

**CONs**

- GAIE support is only an experimental extension point ([EP-10411](https://github.com/kgateway-dev/kgateway/blob/main/design/10411-gateway-api-inference-extension-support.md), explicitly "not for production traffic"); its AI Gateway API for LLM providers/prompt policies ([EP-10494](https://github.com/kgateway-dev/kgateway/blob/main/design/10494-add-support-for-ai-gateway-apis.md)) is still a proposal. **Fails the R2 hard requirement today.**
- No dedicated LLM inference metrics or Grafana dashboards; observability is explicitly out of scope of its AI EPs.

## Decision

Adopt **Agent Router** (formerly Envoy AI Gateway) as the AI gateway for the `ai` tenant, deployed with **Envoy Gateway** as the Gateway API implementation for AI traffic.

Rationale:

1. **R2 is the gate.** Only Agent Router, agentgateway and llm-d implement GAIE `InferencePool` in a usable form; kgateway is experimental and out.
2. **R3 favors Agent Router.** It is the only candidate with GAIE *and* inference metrics on by default (OTel GenAI `gen_ai.*`: TTFT, TPOT, token usage, request duration) *and* a ready-to-import Grafana dashboard. agentgateway's metrics are equally good (and add cost tracking) but it is configuration-first rather than Gateway-API-first; llm-d's dashboards are the best of the four but come with the whole serving platform.
3. **R4 is decisive against llm-d.** Its headline features (P/D disaggregation, KV-cache management across fleets) target multi-GPU deployments; on one 24 GB GPU the tenant would inherit the platform's complexity without its main benefits. A larger/second GPU is being considered but not decided — see [Single-GPU optimizations and the second-GPU question](#single-gpu-optimizations-and-the-second-gpu-question) for why deferring llm-d costs nothing.
4. **R1/R5 fit Agent Router exactly**: one OpenAI-compatible endpoint for opencode, Open WebUI, n8n and MCP clients, with auth, quotas, failover and usage attribution at the edge — without a second serving stack.

**Gateway API implementation.** Deploy Envoy Gateway (the implementation Agent Router is built on) inside the `ai` tenant and point AI `HTTPRoute`s at it via `parentRef`. Traefik remains the cluster-wide Gateway API implementation for all other tenants. A full cluster-wide Traefik replacement is out of scope here — it is a separate decision with a much larger blast radius.

## Single-GPU optimizations and the second-GPU question

The open question: *is it worth starting with llm-d now to learn LLM-inference optimization, in case a larger GPU lands later?* Short answer: **no — and deferring costs nothing, because both routes share the same substrate.**

**How "better" is llm-d's observability, and does it rely on Envoy?**

llm-d is not a proxy. Its Router is any L7 proxy (Istio, Envoy Gateway, agentgateway, Envoy AI Gateway — i.e. Envoy-family data planes) plus the **EPP** (Endpoint Picker), a custom llm-d service the proxy consults per request over Envoy's `ext_proc` protocol; the `InferencePool` CRD wires the EPP into the proxy. So: the data plane relies on an Envoy-family proxy, but the *observability artifacts are custom llm-d work* — the `llm_d_epp_*` metric family (TTFT/TPOT/ITL/NTPOT per model and priority, KV-cache utilization and queue depth per endpoint, prefix-indexer hit ratios, flow-control saturation, SLO violations), 13 Grafana dashboards, and metric-reference docs. Crucially, most of the underlying data is the **model server's own** Prometheus metrics (vLLM/SGLang `/metrics`) plus the EPP's request accounting — the same metrics already scraped today. Its vLLM overview dashboard, for example, is pure vLLM metrics and can be imported into the existing Grafana without installing any llm-d component. What Agent Router's `gen_ai.*` metrics (TTFT, TPOT, token usage, request duration) do not cover is the multi-endpoint layer: KV-cache utilization spread, per-endpoint queues, prefix-routing hit ratios — which only have a signal when there is more than one endpoint.

**Do llm-d's optimizations help a single GPU?**

No — its differentiators are *routing* features, and routing needs choices. With one GPU and `--max-num-seqs=1`, the EPP scheduler has exactly one candidate per pool: KV-cache-affinity placement, load-aware balancing, P/D disaggregation, flow control and SLO-aware scheduling all degenerate to "forward to the only pod." The EPP metrics would mostly be flat lines.

**What does help on one GPU today (no llm-d required):**

- **Prefix caching — yes, it suits a single GPU.** This is an *engine-level* feature, not a routing feature: vLLM's V1 engine enables automatic prefix caching by default (the commented-out `vllm-stack` values enable it explicitly; the current KServe `LLMInferenceService` can add `--enable-prefix-caching` to be explicit). It pays off for agentic workloads (opencode) where system prompts and conversation prefixes repeat across requests, even with serialized requests. It is measurable without any gateway: vLLM exports `vllm:prefix_cache_hits_total` / `vllm:prefix_cache_hit_rate`. llm-d's "prefix cache" feature is a different thing — it *routes* requests to the replica that already holds the prefix, which is meaningless with one replica.
- Chunked prefill / token-budget control (`--max-num-batched-tokens=1024` in the current manifest), FP8 KV cache (`--kv-cache-dtype=fp8`), sleep mode (llama.cpp and vLLM), PagedAttention (inherent to vLLM) — all already in play or engine-level.
- Speculative decoding (MTP drafter) is the obvious next lever but is blocked by VRAM ("Drafter does not fit in VRAM", `qwen38-27b-nvfp4-llminferenceservice.yaml:49-50`); no gateway fixes that — only more/faster VRAM.

**Why deferring llm-d costs nothing when the second GPU decision lands.**

Both Agent Router and llm-d sit on the same GAIE substrate: `InferencePool` + an EPP consulted by an Envoy-family proxy. Agent Router already runs a GAIE EPP today; llm-d's EPP is an extension of the GAIE reference EPP. Adopting llm-d later is therefore an *upgrade of the same control plane* (swap/extend the EPP, add the model-server recipes) — not a rewrite of routing, dashboards or InferencePool wiring. The learnable, durable layer is GAIE itself, which the chosen design teaches now.

## Consequences

### Positive

- **POS-001**: One OpenAI-compatible entrypoint for all AI clients — per-engine endpoint configuration disappears (R1).
- **POS-002**: Request-level TTFT/TPOT/token-usage/duration metrics for *all* traffic, including llama.cpp whose engine metrics are disabled — closing the gap at `llamacpp-statefulset.yaml:98-100` and giving a measurable baseline for inference optimization (R3).
- **POS-003**: GAIE `InferencePool` + endpoint picker enable LLM-aware routing (prefix/KV-cache-aware scheduling) as the fleet grows (R2).
- **POS-004**: Auth, quotas, failover and usage attribution are available at the edge from day one (R5).
- **POS-005**: Importable Grafana dashboards provide out-of-the-box TTFT percentiles, token usage, QPS and error-rate visualization (R3).

### Negative

- **NEG-001**: New Envoy control plane (Envoy Gateway + Agent Router controllers + EPP) — more components to patch than Traefik alone.
- **NEG-002**: Two Gateway API implementations coexist (Traefik cluster-wide, Envoy Gateway for `ai`); routes must choose their `parentRef` deliberately, and a future full migration to Envoy Gateway is a separate decision.
- **NEG-003**: llama.cpp engine-level metrics stay disabled while the sleep model is in use; gateway-side request metrics compensate, but engine-side GPU telemetry (decode speeds, KV stats) remains unavailable until [ggml-org/llama.cpp#20227](https://github.com/ggml-org/llama.cpp/issues/20227) is resolved.
- **NEG-004**: Young, recently renamed project (repo and website moved; API group preserved) — expect some link/doc churn and a smaller community than the Envoy Gateway or Istio projects.

## Alternatives Considered

### agentgateway

- **ALT-001**: **Description**: Linux Foundation AI gateway (Rust data plane, Go controller) with implemented GAIE `InferencePool` support and rich `agentgateway_gen_ai_*` metrics including per-request cost tracking.
- **ALT-002**: **Rejection Reason**: Strong runner-up. Rejected because its configuration-first model is less idiomatic for this Gateway-API-native Flux tenant, its InferencePool track record is shorter, and the Rust data plane adds an unfamiliar debugging surface at a point where the Envoy family is already acceptable for the cluster.

### llm-d

- **ALT-003**: **Description**: CNCF sandbox LLM serving platform shipping the reference GAIE EPP/router, 13 Grafana dashboards and cost tracking, plus KV-cache-aware serving.
- **ALT-004**: **Rejection Reason**: Rejected for scale: it is a full serving platform requiring a separate Gateway API implementation (Istio or Envoy Gateway) plus its own router/EPP/monitoring stack — the largest operational footprint of the four — to deliver P/D and KV-cache features a single-GPU homelab cannot use yet (a second GPU is under consideration but not decided). Its routing intelligence needs more than one endpoint, and its best observability pieces (vLLM dashboards, engine metrics) are importable without adopting the platform. Revisit when the second-GPU decision is made — the shared GAIE InferencePool/EPP substrate makes that an upgrade, not a rewrite.

### kgateway

- **ALT-005**: **Description**: Mature CNCF Gateway API implementation (Solo.io) with AI APIs proposed for a later version.
- **ALT-006**: **Rejection Reason**: Rejected on the hard requirement: GAIE `InferencePool` support is an experimental extension point ("not for production traffic") and its AI Gateway APIs are still proposals, with no LLM metrics or dashboards today.

### No gateway (status quo)

- **ALT-007**: **Description**: Keep per-engine endpoints and Traefik; add only engine-level metrics.
- **ALT-008**: **Rejection Reason**: Cannot satisfy R2 (no `InferencePool`), leaves the llama.cpp metrics gap (R3) and the per-endpoint configuration burden (R1).

## Implementation Notes

- **IMP-001**: Add `infrastructure/ai-gateway/` with HelmReleases for Envoy Gateway and Agent Router (charts from the agent-router repo), plus Kustomizations for the tenant's `Gateway`, `InferencePool` (llama.cpp + vLLM backends) and `HTTPRoute` in the `ai` namespace.
- **IMP-002**: Keep llama.cpp's sleep configuration (`--sleep-idle-seconds 3600`); gateway-side per-request metrics are unaffected by the backend sleeping between scrapes.
- **IMP-003**: Add ServiceMonitors for the Agent Router / Envoy Gateway metrics endpoints and import the bundled Grafana dashboard into the cluster's Grafana.
- **IMP-004**: Point existing clients (Open WebUI, opencode, n8n) at the gateway's OpenAI-compatible endpoint; keep the per-engine HTTPRoutes as fallback until failover is verified.
- **IMP-005**: Success criteria: `gen_ai.*` metrics present in Prometheus for both llama.cpp and vLLM traffic; TTFT/TPOT percentiles rendering on the imported dashboard; the `InferencePool`-backed `HTTPRoute` routing correctly to both engines.
- **IMP-006**: Capture llm-d's observability value without its footprint: import the `llm-d-vllm-overview.json` dashboard (pure vLLM metrics) and add a `vllm:prefix_cache_hit_rate` panel; make prefix caching explicit in the KServe `LLMInferenceService` args if the hit-rate metric is absent.
- **IMP-007**: When the second-GPU question is decided: if yes, revisit prefill/decode disaggregation (vLLM distserve or llm-d) — this gateway choice does not preclude it and the GAIE InferencePool/EPP substrate carries over.

## References

- **REF-001**: Modular handbook — LLM inference metrics: <https://handbook.modular.com/llm-inference-basics/llm-inference-metrics/>
- **REF-002**: Modular handbook — inference optimization: <https://handbook.modular.com/inference-optimization/>
- **REF-003**: Gateway API Inference Extension: <https://gateway-api-inference-extension.sigs.k8s.io/> and <https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/>
- **REF-004**: Agent Router (v1.2.0, GAIE v1.6.2): <https://github.com/theagentrouter/agent-router>
- **REF-005**: agentgateway (v1.7.0): <https://github.com/agentgateway/agentgateway>
- **REF-006**: llm-d (v1.0.0): <https://github.com/llm-d/llm-d>
- **REF-007**: kgateway (v2.4.7; GAIE EP-10411 experimental): <https://github.com/kgateway-dev/kgateway>
- **REF-008**: llama.cpp metrics/sleep issue: <https://github.com/ggml-org/llama.cpp/issues/20227>
