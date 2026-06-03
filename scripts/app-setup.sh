#!/bin/bash
set -euo pipefail
exec > /var/log/app-setup.log 2>&1

echo "==> Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done

echo "==> Installing system packages..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-pip python3-venv nginx git curl openssl ca-certificates

echo "==> Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

echo "==> Logging in with managed identity..."
az login --identity

echo "==> Downloading TLS certificate from Key Vault..."
mkdir -p /etc/ssl/quiz-app
az keyvault secret download \
    --vault-name ${kv_name} \
    --name quiz-agw-tls \
    --file /tmp/cert.pfx \
    --encoding base64

echo "==> Extracting certificate and private key from PFX..."
# Try modern OpenSSL first, fall back to legacy mode for older PFX formats
openssl pkcs12 -in /tmp/cert.pfx -nokeys \
    -out /etc/ssl/quiz-app/cert.crt -password pass: 2>/dev/null \
  || openssl pkcs12 -in /tmp/cert.pfx -nokeys -legacy \
    -out /etc/ssl/quiz-app/cert.crt -password pass:

openssl pkcs12 -in /tmp/cert.pfx -nocerts -nodes \
    -out /etc/ssl/quiz-app/cert.key -password pass: 2>/dev/null \
  || openssl pkcs12 -in /tmp/cert.pfx -nocerts -nodes -legacy \
    -out /etc/ssl/quiz-app/cert.key -password pass:

chmod 600 /etc/ssl/quiz-app/cert.key
rm -f /tmp/cert.pfx

echo "==> Cloning app from GitHub..."
git clone ${github_repo} /opt/quiz-app
cd /opt/quiz-app

echo "==> Creating virtual environment and installing packages..."
python3 -m venv venv
source venv/bin/activate
pip install --quiet -r requirements.txt
pip install --quiet gunicorn

echo "==> Writing .env..."
cat > /opt/quiz-app/.env <<'ENV_EOF'
ENTRA_CLIENT_ID=${entra_client_id}
ENTRA_CLIENT_SECRET=${entra_client_secret}
ENTRA_TENANT_ID=${entra_tenant_id}
REDIRECT_URI=https://${domain}/auth/callback
FLASK_SECRET_KEY=${flask_secret_key}
DATABASE_URL=postgresql+psycopg2://quizadmin:${db_password}@${db_private_ip}:5432/quiz
ENV_EOF

echo "==> Waiting for PostgreSQL at ${db_private_ip}:5432..."
i=0
until python3 -c "
import psycopg2
psycopg2.connect(host='${db_private_ip}', user='quizadmin', password='${db_password}', database='quiz').close()
" 2>/dev/null; do
    i=$((i+1))
    echo "Attempt $i — PostgreSQL not ready, retrying in 15s..."
    sleep 15
done
echo "PostgreSQL ready after $i attempt(s)."

echo "==> Initialising database schema..."
python3 -c "from app import create_app; create_app()"

echo "==> Creating systemd service for gunicorn..."
cat > /etc/systemd/system/quiz-app.service <<'SVC_EOF'
[Unit]
Description=Quiz App (gunicorn)
After=network.target

[Service]
User=root
WorkingDirectory=/opt/quiz-app
Environment=PATH=/opt/quiz-app/venv/bin
ExecStart=/opt/quiz-app/venv/bin/gunicorn -w 2 -b 127.0.0.1:5000 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable quiz-app
systemctl start quiz-app

echo "==> Configuring nginx with TLS (HTTP redirects to HTTPS)..."
cat > /etc/nginx/sites-available/quiz-app <<'NGINX_EOF'
server {
    listen 80;
    server_name ${domain};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name ${domain};

    ssl_certificate     /etc/ssl/quiz-app/cert.crt;
    ssl_certificate_key /etc/ssl/quiz-app/cert.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/quiz-app /etc/nginx/sites-enabled/quiz-app
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "==> Setup complete. App running at https://${domain}"
