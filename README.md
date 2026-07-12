# Vane (Perplexica) Self-Hosted AI Search Setup

Setup notes and automation script for running Vane (formerly Perplexica) 
with local Ollama models and Nginx reverse proxy on an E2E Networks GPU pod.

## Stack
- Vane (Node.js/Next.js, run natively — no Docker)
- Ollama (qwen3:30b, qwen2.5:14b) — GPU-accelerated (NVIDIA L4)
- Nginx reverse proxy with Basic Auth

## Key challenges solved
- E2E pod is Kubernetes-based (no systemd, no Docker networking privileges)
- Docker's bridge network creation fails due to iptables permission restrictions
- Workaround: run Vane via `yarn start` natively instead of Docker
- Ollama GPU auto-detection needs `pciutils`/`lshw` installed first

## Usage
Run after every pod restart (pod storage is ephemeral):
\`\`\`bash
bash setup_vane_pod.sh
\`\`\`
