#!/bin/bash
set -euo pipefail

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# ---------- Header ----------
echo -e "${BOLD}${BLUE}=== Jexactyl v3 → Jexpanel v4 Migration Script ===${RESET}"
echo

# ---------- Step 1: Choose directory ----------
echo -e "${BOLD}Choose the working directory:${RESET}"
echo "1) /var/www/jexactyl"
echo "2) /var/www/pterodactyl"
read -rp "> " choice

if [[ "$choice" == "2" ]]; then
  dir="/var/www/pterodactyl"
else
  dir="/var/www/jexactyl"
fi

echo -e "${BLUE}→ Working directory set to:${RESET} $dir"
echo

cd "$dir"

# ---------- Step 2: Backup ----------
read -rp "Do you want to create a backup of database and files? (y/n): " backup
if [[ "$backup" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}→ Creating backup...${RESET}"
  cp -R "$dir" "${dir}-backup"
  mysqldump panel > "${dir}/backup.sql"
  echo -e "${GREEN}✔ Backup created at ${dir}-backup and ${dir}/backup.sql${RESET}"
else
  echo -e "${YELLOW}⚠ Backup skipped. (Not recommended)${RESET}"
fi
echo

# ---------- Step 3: Stop Panel ----------
echo -e "${BLUE}→ Stopping the panel...${RESET}"
php artisan down
echo -e "${GREEN}✔ Panel is now in maintenance mode.${RESET}"
echo

# ---------- Step 4: Download new version ----------
echo -e "${BLUE}→ Downloading Jexpanel v4...${RESET}"
curl -Lo panel.tar.gz https://github.com/Jexactyl/Jexactyl/releases/download/v4.0.0-rc2/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
echo -e "${GREEN}✔ Files extracted and permissions set.${RESET}"
echo

# ---------- Step 5: Update dependencies ----------
echo -e "${BLUE}→ Updating dependencies...${RESET}"
rm -rf vendor
rm -f app/Console/Commands/Environment/EmailSettingsCommand.php
composer install --no-dev --optimize-autoloader
echo -e "${GREEN}✔ Dependencies installed.${RESET}"
echo

# ---------- Step 6: Clear cache ----------
echo -e "${BLUE}→ Clearing cache...${RESET}"
php artisan optimize:clear
echo -e "${GREEN}✔ Cache cleared.${RESET}"
echo

# ---------- Step 7: Database cleanup ----------
echo -e "${BLUE}→ Updating database schema...${RESET}"
mysql -u root -p <<EOF
USE panel;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS ticket_messages;
DROP TABLE IF EXISTS theme;
ALTER TABLE nodes DROP COLUMN IF EXISTS deployable;
EOF
echo -e "${GREEN}✔ Old tables/columns removed.${RESET}"
echo

# ---------- Step 8: Run migrations ----------
echo -e "${BLUE}→ Running database migrations...${RESET}"
php artisan migrate --seed --force
echo -e "${GREEN}✔ Database updated.${RESET}"
echo

# ---------- Step 9: Fix permissions ----------
echo -e "${BLUE}→ Setting correct permissions...${RESET}"

if id "nginx" &>/dev/null; then
  chown -R nginx:nginx "$dir"/*
elif id "apache" &>/dev/null; then
  chown -R apache:apache "$dir"/*
else
  chown -R www-data:www-data "$dir"/*
fi

echo -e "${GREEN}✔ Permissions updated.${RESET}"
echo

# ---------- Step 10: Restart queues & bring panel online ----------
echo -e "${BLUE}→ Restarting queues and starting panel...${RESET}"
php artisan queue:restart
php artisan up
echo -e "${GREEN}✔ Panel is online.${RESET}"
echo

# ---------- Done ----------
echo -e "${BOLD}${GREEN}✅ Migration completed successfully!${RESET}"
echo -e "${YELLOW}⚠ If stuck on 'Welcome to Jexpanel', check APP_ENVIRONMENT_ONLY=false in .env${RESET}"
