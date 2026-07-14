#!/bin/bash
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
PUBLIC_IP="91.203.132.218"

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
