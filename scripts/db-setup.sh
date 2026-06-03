#!/bin/bash
set -euo pipefail
exec > /var/log/db-setup.log 2>&1

echo "==> Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done

echo "==> Installing PostgreSQL and Azure CLI..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib curl ca-certificates
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

echo "==> Configuring PostgreSQL to accept connections from app subnet..."
PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -1)
PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
echo "host  quiz  quizadmin  10.0.1.0/24  scram-sha-256" >> "$PG_HBA"

systemctl restart postgresql

echo "==> Creating quizadmin user and empty quiz database..."
sudo -u postgres psql <<'SQL'
CREATE USER quizadmin WITH PASSWORD '${db_password}';
CREATE DATABASE quiz OWNER quizadmin ENCODING 'UTF8' TEMPLATE template0 LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8';
SQL

sudo -u postgres psql -d quiz <<'SQL'
GRANT ALL ON SCHEMA public TO quizadmin;
ALTER SCHEMA public OWNER TO quizadmin;
SQL

echo "==> Downloading backup '${backup_file}' from blob storage..."
az storage blob download \
    --account-name quizdbbackupivansto \
    --account-key "${storage_key}" \
    --container-name db-backups \
    --name "${backup_file}" \
    --file /tmp/restore.sql

echo "==> Restoring database from backup..."
sudo -u postgres psql -d quiz < /tmp/restore.sql

rm -f /tmp/restore.sql

echo "==> DB setup complete. Database restored from ${backup_file}."
