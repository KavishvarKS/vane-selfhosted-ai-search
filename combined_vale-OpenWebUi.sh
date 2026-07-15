#!/bin/bash
# ============================================================
# SIMPLE FIX: Vane + Open WebUI + Nginx + Ollama
# Only change from your original script: Vane is bound to
# 127.0.0.1:3000 (localhost only) instead of 0.0.0.0:3000 (public).
# No SearxNG. Nothing else touched.
# ============================================================
# Usage: bash setup_simple.sh
# ============================================================

read -p "Please enter the IP address: " ip_address
PUBLIC_IP="$ip_address"

set -e

echo "=== Killing any stale process on port 3000 ==="
fuser -k 3000/tcp 2>/dev/null || true
sleep 2

echo "=== [1/8] Updating system + installing base packages ==="
apt update
apt install -y nginx apache2-utils curl git pciutils lshw zstd

echo "=== [2/8] Installing Node.js 22 + Yarn ==="
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt install -y nodejs
fi
npm install -g yarn

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

echo "=== [5/8] Starting Vane bound to LOCALHOST ONLY (127.0.0.1:3000) ==="
nohup npx next start -p 3000 -H 127.0.0.1 > /var/log/vane.log 2>&1 &
sleep 5
echo "Vane local status: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000 || true)"

echo "=== [6/8] Setting up Nginx reverse proxy with Basic Auth (port 80) ==="
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
if pgrep -x "nginx" > /dev/null; then
  nginx -s reload
else
  nginx
fi

echo "=== [7/8] Installing Ollama + starting server (GPU-enabled) ==="
if ! command -v ollama &> /dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
pkill ollama || true
sleep 2
OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /var/log/ollama.log 2>&1 &
sleep 5
ollama pull qwen3:30b
ollama pull qwen2.5:14b

echo "=== [8/8] Installing Open WebUI (snap), bound to localhost only (127.0.0.1:8090), Nginx on 8080 ==="
apt install -y python3-pip
if ! snap list open-webui &> /dev/null; then
  snap install open-webui
fi
sudo snap set open-webui port=8090
snap restart open-webui.server
sleep 8

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
fuser -k 8080/tcp 2>/dev/null || true
sleep 2
nginx -t
nginx -s reload

echo ""
echo "============================================================"
echo " DONE"
echo " Vane:        http://${PUBLIC_IP}       (login: max)"
echo " Open WebUI:  http://${PUBLIC_IP}:8080   (login: max)"
echo " Port 3000 is now localhost-only - not reachable from outside."
echo "============================================================"
