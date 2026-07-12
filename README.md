# Vane (Perplexica) Self-Hosted AI Search Setup

Setup notes and a one-shot automation script for running **Vane** (formerly known as
Perplexica) — a self-hosted, AI-powered search engine — backed by a local **Ollama**
model and fronted by **Nginx** with Basic Auth, running on an **E2E Networks GPU pod**.

This repo documents the full setup process, the platform-specific issues encountered
along the way (and how they were worked around), and a reusable script to re-provision
everything after a pod restart.

---

## Stack

| Component | Role |
|---|---|
| **Vane (Perplexica)** | Search-first AI interface (Node.js / Next.js), run natively — no Docker |
| **Ollama** | Local LLM inference engine, GPU-accelerated (tested on NVIDIA L4) |
| **Nginx** | Reverse proxy + Basic Auth, so the app is only reachable with a login |
| Models used | `qwen3:30b` (MoE, best balance of speed + reasoning for ~24GB VRAM), `qwen2.5:14b` (lighter/faster fallback) |

---

## Why this setup looks the way it does

E2E's GPU "pod" tier is Kubernetes-based, not a traditional VM. That has a few
consequences that shaped this setup:

- **No systemd.** PID 1 is `s6-svscan`, not `systemd`, so `systemctl` commands don't
  work at all. Services (Nginx, Ollama) have to be started as plain background
  processes (`nohup ... &`) instead of managed system services.

- **Docker cannot run containers with networking.** The Docker daemon starts, but
  fails when creating its bridge network:
  ```
  failed to create bridge docker0 via netlink: operation not permitted
  ```
  This is a hard capability restriction on the pod (missing `NET_ADMIN`), not
  something fixable from inside the pod itself. As a result, **Vane cannot be run via
  its provided `docker-compose.yaml`** on this pod tier — it has to be run natively
  with Node.js/Yarn instead.

- **Storage is ephemeral.** Stopping and starting the pod wipes the filesystem
  entirely — installed packages, cloned repos, and downloaded models are all gone on
  next start. This is the reason for the setup script below: rather than repeating ~20
  manual commands every time the pod restarts, one script re-provisions everything.

- **Ollama's GPU auto-detection needs `pciutils`/`lshw`.** Without these installed
  first, Ollama's installer prints a "GPU not detected" warning even though the GPU
  (and NVIDIA driver/CUDA) is actually present and working — confirmed via
  `nvidia-smi`.

> **Note:** none of this applies if you're running on a normal VM (with systemd and
> full root/kernel privileges) — there, Docker works fine and the original
> `docker-compose.yaml` approach from the Vane repo can be used directly instead of
> this native workaround. This script also works on a plain VM, but on a VM you'd
> ideally want `ollama` and `nginx` running as proper systemd services (so they
> survive reboots and auto-restart on crash) rather than background `nohup` processes.

---

## Before you run the script

Open `setup_vane_pod.sh` and update this line near the top of the Nginx section:

```bash
PUBLIC_IP="xxx.xxx.xxx.xxx"
```

**Replace `xxx.xxx.xxx.xxx` with your own pod's public IP.** This is the address
Nginx will listen for and the one you'll use to access Vane in your browser — using
someone else's IP here (like the example above) will not work for you. You can find
your pod's public IP from the E2E dashboard, or from the SSH command you use to
connect to it (e.g. `ssh root@<your-ip>`).

If your pod gets a new public IP after a restart (common with ephemeral pods), update
this line again before re-running the script.

---

## Usage

```bash
chmod +x setup_vane_pod.sh
bash setup_vane_pod.sh
```

Run this after every pod restart, since pod storage does not persist.

On first run, you'll be prompted to set a login password for user `max` — this is
the Basic Auth login Nginx will require before anyone can reach Vane. On later runs
(same pod session), this step is skipped if the password file already exists.

Once complete, the script prints the access URL and the Ollama connection details to
paste into Vane's "Add Connection" screen (`http://localhost:11434`).

---

## Known open issue

External access on port 80 has been inconsistent on this pod tier — SSH (port 22)
is reachable, but HTTP (port 80) has not reliably passed through from the public
internet in testing, despite Nginx correctly listening and responding locally
(confirmed via `curl localhost:80`). This appears to be a pod-level networking/port
exposure configuration on E2E's side rather than anything fixable from inside the
pod. If you hit the same issue, an SSH tunnel is a reliable workaround in the
meantime:

```bash
# run on your own laptop, not on the pod
ssh -L 8080:localhost:80 root@<your-pod-public-ip>
```

Then visit `http://localhost:8080` in your browser.
