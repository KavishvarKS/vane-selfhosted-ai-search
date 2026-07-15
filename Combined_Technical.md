After installing the combined stack, access Vane using the public IP of the server.
 
Then access Open WebUI at public_ip:8080.
 
Default username is "max".
Password is whatever you set at login.
 


--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------






# TECHNICAL.md — What `setup_simple.sh` Actually Does

This file walks through the script step by step. Read this if you want to know
*why* each command is there, not just what it does.

---

## Step 0 — Kill anything already on port 3000
```bash
fuser -k 3000/tcp
```
If Vane was already running from a previous attempt, this frees the port
before we try to start a new instance. Prevents `EADDRINUSE` errors.

## Step 1 — Install base packages
```bash
apt install -y nginx apache2-utils curl git pciutils lshw zstd
```
- `nginx` — the reverse proxy / login wall in front of Vane and Open WebUI
- `apache2-utils` — gives us `htpasswd`, used to create the login password file
- `curl`, `git` — used throughout the script to download things and check status
- `pciutils`, `lshw` — hardware detection tools (used by Ollama to find the GPU)
- `zstd` — compression tool some packages depend on

## Step 2 — Install Node.js + Yarn
Vane is a Next.js (Node.js) application, so it needs Node.js to run and Yarn
to install its dependencies.

## Step 3 — Clone Vane's source code
```bash
git clone https://github.com/ItzCrazyKns/Perplexica.git
```
Downloads the actual application code. Skipped if it's already been cloned once.

## Step 4 — Install dependencies + build
```bash
yarn install
yarn build
```
`yarn install` downloads all the code libraries Vane needs.
`yarn build` compiles the app into a form that can actually run in production
(this is what takes the longest — several minutes).

## Step 5 — Start Vane (localhost only) — **the actual fix**
```bash
nohup npx next start -p 3000 -H 127.0.0.1 > /var/log/vane.log 2>&1 &
```
This is the important line. Breaking it down:
- `next start -p 3000` — starts the built app on port 3000
- `-H 127.0.0.1` — **binds it only to localhost**, so it's unreachable from
  outside the server. Without this flag, the app defaults to `0.0.0.0`
  (all interfaces), which means anyone on the internet could reach it
  directly on port 3000, bypassing the Nginx login wall entirely. This one
  flag is the whole fix.
- `nohup ... &` — runs it in the background, and keeps it running even after
  you close the terminal
- `> /var/log/vane.log 2>&1` — sends all output (normal + errors) to a log
  file, so we can check it later if something breaks

## Step 6 — Set up Nginx as the public-facing login wall
- Creates a password file (`htpasswd`) for user `max`
- Writes an Nginx config that listens on port 80 (the standard "just type the
  IP" port), asks for that login, and then quietly forwards traffic to Vane
  on `127.0.0.1:3000` behind the scenes
- Reloads Nginx to apply the config

This is what makes `http://<ip>` work with a login prompt, while port 3000
itself stays invisible to the outside world.

## Step 7 — Install and start Ollama
Ollama is the engine that actually runs the AI models on the server's GPU.
```bash
OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve &
```
Bound to all interfaces here because both Vane and Open WebUI (running on
the same machine) need to reach it — but since port 11434 isn't referenced
in any Nginx config, it's still not exposed to the public internet in
practice, only reachable from processes on this same server.

Then it downloads two models to use for chat: `qwen3:30b` and `qwen2.5:14b`.

## Step 8 — Install Open WebUI + set up its own Nginx entry
- Installs Open WebUI via `snap`
- Configures it to run internally on port `8090` (not public)
- Writes a second Nginx config, this time listening on port `8080`, which
  again asks for the `max` login before forwarding to `127.0.0.1:8090`
- One extra detail: the `/api` path is set to skip the login check
  (`auth_basic off`). This is needed because Open WebUI's own login page
  makes background calls to `/api` before you've logged in — if those calls
  also got blocked by Nginx's login wall, you'd get stuck in a loop and
  never see the login screen at all.

## Result: what's actually exposed

| Port | Bound to | Reachable from internet? |
|---|---|---|
| 80 | Nginx (all interfaces) | ✅ Yes — Vane, password protected |
| 8080 | Nginx (all interfaces) | ✅ Yes — Open WebUI, password protected |
| 3000 | `127.0.0.1` only | ❌ No |
| 8090 | `127.0.0.1` only | ❌ No |
| 11434 | `0.0.0.0` but unlisted in Nginx | ❌ Not proxied, not intended to be reached externally |

That's the entire setup: two public doors (80 and 8080), both locked with a
password, both quietly forwarding to backend services that can't be reached
any other way.
