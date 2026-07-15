# Self-Hosted AI Search Stack

A private AI search + chat setup running on one E2E Networks server.
Only two things are open to the internet — everything else stays local.

## Architecture

```
                        INTERNET
                            │
                ┌───────────┴───────────┐
                │                       │
           http://IP              http://IP:8080
                │                       │
                ▼                       ▼
        ┌───────────────┐       ┌───────────────┐
        │     Nginx     │       │     Nginx     │
        │  (login wall) │       │  (login wall) │
        └───────┬───────┘       └───────┬───────┘
                │                       │
                ▼                       ▼
        ┌───────────────┐       ┌───────────────┐
        │     Vane      │       │  Open WebUI   │
        │  (search UI)  │       │  (chat UI)    │
        │  localhost    │       │  localhost    │
        │  only         │       │  only         │
        └───────┬───────┘       └───────┬───────┘
                │                       │
                └───────────┬───────────┘
                            ▼
                     ┌─────────────┐
                     │   Ollama    │
                     │ (runs the   │
                     │  AI models) │
                     └─────────────┘
```

## What's Running

| Service | What it does | Who can reach it |
|---|---|---|
| **Nginx** | Login wall (username + password) | Public |
| **Vane** | AI search engine | Public, via Nginx only |
| **Open WebUI** | AI chat interface | Public, via Nginx only |
| **Ollama** | Runs the AI models (qwen3, qwen2.5) | Server only |

## How to Access

| Service | Address | Login |
|---|---|---|
| Vane | `http://<server-ip>` | user: `max` |
| Open WebUI | `http://<server-ip>:8080` | user: `max`, then create an admin account inside |

## Setup

```bash
bash combined_vale-OpenWebUi.sh
```

You'll be asked for the server's public IP, then the script installs and starts everything.

For a full breakdown of what each line of the script does, see **TECHNICAL.md**.
