# Open WebUI Setup (Self-Hosted, behind Nginx)

Setup notes for installing **Open WebUI** — a self-hosted chat interface for local
LLMs — alongside an existing Vane (Perplexica) deployment, on the same machine.
Open WebUI runs on its own Nginx-authenticated port, separate from Vane, sharing the
same login credentials and the same local Ollama backend.

This assumes Vane is already set up and running on port 80 (untouched by this
setup) — Open WebUI is added as a second, independent app on port 8080.

---

## Overview

| Item | Value |
|---|---|
| Public access | `http://<public-ip>:8080` |
| Internal app port | `127.0.0.1:8090` |
| Auth | Nginx Basic Auth (same `.htpasswd` file used for Vane) |
| Install method | Snap package |
| LLM backend | Local Ollama, `http://localhost:11434` |

Like Vane, Open WebUI itself never listens on a public port directly — it's bound
to `127.0.0.1` only, on an internal port. Nginx is the only thing exposed publicly,
and it enforces a login before forwarding any request through to the app.

---

## 1. Installing Open WebUI

Open WebUI is installed via snap in this setup (simpler than pip for keeping it
running as a managed background service):

```bash
apt install -y python3-pip
snap install open-webui
```

## 2. Binding it to an internal-only port

By default, Open WebUI's snap package binds to `127.0.0.1:8080`. Since Nginx needs
port `8080` for itself (as the public-facing port), Open WebUI is moved to `8090`
internally instead:

```bash
sudo snap set open-webui port=8090
snap restart open-webui.server
```

Confirm it's up and listening correctly:

```bash
ss -tlnp | grep 8090
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8090
```

You should see it bound to `127.0.0.1:8090` and a `200` from curl.

---

## 3. Nginx configuration

Create `/etc/nginx/sites-available/openwebui`:

```nginx
server {
    listen 8080;
    server_name <your-public-ip>;

    location /api {
        auth_basic off;
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Why there are two `location` blocks

Open WebUI is a single-page app — actions like "Create Admin Account," sending a
chat message, or loading chat history don't reload the page. Instead, the browser
sends background requests to paths under `/api/...`.

If Basic Auth applied to those requests too, the browser doesn't consistently
resend saved credentials to background API calls the way it does for the initial
page load. The visible symptom is an **infinite login loop**: the main page loads
fine after you enter the password, but every button click inside the app
re-triggers the Nginx login prompt and never actually completes the action.

The fix is to split the config into two rules:
- **`location /api`** → `auth_basic off;` — lets the app's internal API traffic
  through freely, since it's the app talking to itself, not a new outside visitor
- **`location /`** → keeps `auth_basic` on — still requires login for anyone
  loading the app itself

This preserves the security goal (nobody gets in without the password) while
letting the app function normally once you're past that first login screen.

Enable the config and reload Nginx:

```bash
ln -sf /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/openwebui
nginx -t
nginx -s reload
```

---

## 4. Sharing the login with Vane

Open WebUI uses the **same** `.htpasswd` file as Vane — one username/password
protects both apps. If it doesn't exist yet:

```bash
htpasswd -c /etc/nginx/.htpasswd max
```

If it already exists (because Vane's setup created it first), skip this — Open
WebUI's config already points at the same file (`/etc/nginx/.htpasswd`).

To change the password later:

```bash
htpasswd /etc/nginx/.htpasswd max
```

(no `-c` flag here — that flag creates a brand-new file and would wipe out the
existing one)

---

## 5. Connecting Open WebUI to Ollama

This step happens **inside Open WebUI itself**, not through Nginx — it's a direct,
internal, machine-to-machine connection.

Go to **Admin Panel → Settings → Connections** inside Open WebUI, and set:

```
http://127.0.0.1:11434
```
or
```
http://localhost:11434
```

Ollama needs no authentication for this, since it only listens on `127.0.0.1` and
is never exposed to the public internet — only processes running on the same
machine (like Open WebUI and Vane) can reach it.

---

## 6. Resetting a forgotten Open WebUI account

Open WebUI stores hashed (not reversible) passwords in a local SQLite database, so
there's no way to look up or recover a forgotten password directly. The simplest
fix is a full reset — the next person to sign up becomes the new admin
automatically:

```bash
snap stop open-webui.server
rm /var/snap/open-webui/common/data/webui.db
snap start open-webui.server
```

Then visit `http://<public-ip>:8080`, and sign up again with a fresh
email/password.

---

## 7. Common issue: port already in use

If Nginx fails to reload with an error like:

```
bind() to 0.0.0.0:8080 failed (98: Address already in use)
```

Something else (often a leftover Open WebUI or test process) is already holding
port 8080. Find and remove it, then reload:

```bash
lsof -i :8080
kill -9 <PID>
nginx -s reload
```

Nginx treats a reload as one all-or-nothing action — if any one of its sites fails
to bind, the whole reload can silently fall back to a stale state. If things seem
inconsistent after an edit, this port-conflict check is the first thing to rule
out.

---

## Quick reference: verifying everything is up

```bash
# Open WebUI app itself (internal, should never be reachable from outside)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8090

# Ollama
curl -s http://127.0.0.1:11434

# Through Nginx (should return 401 = asking for login — this is correct)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080
```

Then test in a browser:

```
http://<your-public-ip>:8080   → Nginx login → Open WebUI
```
