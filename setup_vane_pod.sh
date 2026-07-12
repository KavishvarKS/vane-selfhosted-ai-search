#!/bin/bash
# ============================================================
# Vane (Perplexica) + Nginx + Ollama setup script
# For E2E Networks POD (Kubernetes-based, no Docker, no systemd)
# Run this fresh after every pod restart (pod storage is wiped)
# ============================================================
# Usage: bash setup_vane_pod.sh
# ============================================================

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
PUBLIC_IP="xxx.xxx.xxx.xxx"

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
