#!/bin/bash
# ============================================================
# Vane (Perplexica) + Nginx + Ollama setup script
# For E2E Networks POD (Kubernetes-based, no Docker, no systemd)
# Run this fresh after every pod restart (pod storage is wiped)
# ============================================================
# Usage: bash setup_vane_pod.sh
# ============================================================

read -p "Please enter the IP address: " ip_address

set -e  # stop on first real error (comment out this line if you want it to keep going despite errors)

echo "=== [1/8] Updating system + installing base packages ==="
apt update
apt install -y nginx apache2-utils curl git pciutils lshw zstd

echo "=== [2/8] Installing Node.js 22 + Yarn ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
npm install -g yarn
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "Yarn version: $(yarn --version)"

echo "=== [3/8] Cloning Vane (Perplexica) repo ==="
cd ~
if [ -d "Perplexica" ]; then
  echo "Perplexica folder already exists, skipping clone"
else
  git clone https://github.com/ItzCrazyKns/Perplexica.git
fi
cd ~/Perplexica

echo "=== [4/8] Installing dependencies + building Vane ==="
yarn install
yarn build

echo "=== [5/8] Starting Vane in the background (port 3000) ==="
nohup yarn start > /var/log/vane.log 2>&1 &
sleep 5
VANE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || true)
echo "Vane status on port 3000: $VANE_STATUS"

echo "=== [6/8] Setting up Nginx reverse proxy with Basic Auth ==="
# NOTE: update PUBLIC_IP below if your pod's public IP changes after restart
PUBLIC_IP="$ip_address"

# Create password file only if it doesn't already exist (so you don't get repeatedly prompted)
if [ ! -f /etc/nginx/.htpasswd ]; then
  echo ">>> Set a login password for user 'max' when prompted:"
  htpasswd -c /etc/nginx/.htpasswd max
else
  echo ".htpasswd already exists, skipping password creation"
fi

cat > /etc/nginx/sites-available/vane << EOF
server {
    listen 80;
    server_name ${PUBLIC_IP};

    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/vane /etc/nginx/sites-enabled/vane
rm -f /etc/nginx/sites-enabled/default
nginx -t

# Start or reload nginx (no systemd here, so handle both cases)
if pgrep -x "nginx" > /dev/null; then
  nginx -s reload
else
  nginx
fi
echo "Nginx status on port 80: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:80 || true)"

echo "=== [7/8] Installing Ollama + starting server (GPU-enabled) ==="
if ! command -v ollama &> /dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

# Kill any stale instance, then start fresh listening on all interfaces
pkill ollama || true
sleep 2
OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /var/log/ollama.log 2>&1 &
sleep 5
echo "Ollama status: $(curl -s http://localhost:11434 || true)"

echo "=== [8/8] Pulling models (skips if already present) ==="
ollama pull qwen3:30b
ollama pull qwen2.5:14b

echo ""
echo "============================================================"
echo " SETUP COMPLETE"
echo " Access Vane at: http://${PUBLIC_IP}"
echo " Login user: max  (password: whatever you set above)"
echo " In Vane's Add Connection screen, use:"
echo "   Base URL: http://localhost:11434"
echo "============================================================"





# ============================================================
# Open WebUI setup (standalone) — behind Nginx on port 8080
# Assumes Nginx is already installed and .htpasswd already exists
# ============================================================
# Usage: bash setup_openwebui.sh
# ============================================================

set -e

# ------------------------------------------------------------
# EDIT THIS before running: your VM/pod's own public IP
# ------------------------------------------------------------

echo "=== [1/5] Installing Open WebUI (snap) ==="
apt install -y python3-pip
if ! snap list open-webui &> /dev/null; then
  snap install open-webui
fi

echo "=== [2/5] Binding Open WebUI to internal-only port 8090 ==="
sudo snap set open-webui port=8090
snap restart open-webui.server
sleep 8
echo "Open WebUI internal status (127.0.0.1:8090): $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090 || true)"

echo "=== [3/5] Ensuring shared Basic Auth password file exists ==="
if [ ! -f /etc/nginx/.htpasswd ]; then
  echo ">>> Set a login password for user 'max' when prompted:"
  htpasswd -c /etc/nginx/.htpasswd max
else
  echo ".htpasswd already exists, skipping password creation"
fi

echo "=== [4/5] Writing Nginx config for Open WebUI (public port 8080) ==="
cat > /etc/nginx/sites-available/openwebui << EOF
server {
    listen 8080;
    server_name ${PUBLIC_IP};

    location /api {
        auth_basic off;
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/openwebui

echo "=== [5/5] Freeing port 8080 of any stale process, then starting Nginx ==="
# Fix for "Address already in use" bind failure if something already holds 8080
fuser -k 8080/tcp 2>/dev/null || true
sleep 2

nginx -t
if pgrep -x "nginx" > /dev/null; then
  nginx -s reload
else
  nginx
fi

sleep 2
echo ""
echo "============================================================"
echo " Verifying..."
ss -tlnp | grep -E ":8080|:8090" || true
echo "============================================================"
echo " SETUP COMPLETE"
echo " Open WebUI: http://${PUBLIC_IP}:8080  (login: max)"
echo " Ollama connection URL (inside Open WebUI): http://localhost:11434"
echo "============================================================"
echo ""
echo "If port 8080 shows a 'bind failed / Address already in use' error,"
echo "an old process is still holding it. Find and kill it manually:"
echo "   lsof -i :8080"
echo "   kill -9 <PID>"
echo "then re-run: nginx -s reload"
