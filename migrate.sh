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
echo -e "${BOLD}${BLUE}=== Jexactyl v3 → v4 Migration Script ===${RESET}"
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

# ---------- Step 2: Backup ----------
read -rp "Do you want to create a backup? (y/n): " backup
if [[ "$backup" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}→ Creating backup...${RESET}"
  cp -R "$dir" "${dir}-backup"
  echo -e "${GREEN}✔ Backup created at ${dir}-backup${RESET}"
else
  echo -e "${YELLOW}⚠ Backup skipped. (Not recommended)${RESET}"
fi
echo

cd "$dir"

# ---------- Step 3: Stop Panel ----------
echo -e "${BLUE}→ Stopping the panel...${RESET}"
php artisan down
echo -e "${GREEN}✔ Panel is now in maintenance mode.${RESET}"
echo

# ---------- Step 4: Download new version ----------
echo -e "${BLUE}→ Downloading Jexactyl v4...${RESET}"
curl -L -o panel.tar.gz https://github.com/Jexactyl/Jexactyl/releases/download/v4.0.0-beta7/panel.tar.gz
tar -xzf panel.tar.gz
rm panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
echo -e "${GREEN}✔ Files extracted and permissions set.${RESET}"
echo

# ---------- Step 5: Patch EmailSettingsCommand ----------
file="$dir/app/Console/Commands/Environment/EmailSettingsCommand.php"
if [[ -f "$file" ]]; then
  sed -i "s|Jexactyl\\\\Traits\\\\Commands\\\\EnvironmentWriterTrait|Everest\\\\Traits\\\\Commands\\\\EnvironmentWriterTrait|g" "$file"
  echo -e "${GREEN}✔ File patched:${RESET} $file"
else
  echo -e "${YELLOW}⚠ File not found:${RESET} $file"
fi
echo

# ---------- Step 6: Install dependencies ----------
echo -e "${BLUE}→ Installing PHP dependencies...${RESET}"
composer install --no-dev --optimize-autoloader
echo -e "${GREEN}✔ Dependencies installed.${RESET}"
echo

# ---------- Step 7: Clear cache ----------
echo -e "${BLUE}→ Clearing cache...${RESET}"
php artisan optimize:clear
echo -e "${GREEN}✔ Cache cleared.${RESET}"
echo

# ---------- Step 8: Remove old migrations ----------
echo -e "${BLUE}→ Removing old migrations...${RESET}"
rm -f "$dir/database/migrations/2024_03_30_211213_create_tickets_table.php"
rm -f "$dir/database/migrations/2024_03_30_211447_create_ticket_messages_table.php"
rm -f "$dir/database/migrations/2024_04_15_203406_add_theme_table.php"
rm -f "$dir/database/migrations/2024_05_01_124250_add_deployable_column_to_nodes_table.php"
echo -e "${GREEN}✔ Old migrations removed.${RESET}"
echo

# ---------- Step 9: Run migrations ----------
echo -e "${BLUE}→ Running database migrations...${RESET}"
php artisan migrate --seed --force
echo -e "${GREEN}✔ Database updated.${RESET}"
echo

# ---------- Step 10: Fix permissions ----------
echo -e "${BLUE}→ Setting correct permissions...${RESET}"
chown -R www-data:www-data "$dir"/*
echo -e "${GREEN}✔ Permissions updated.${RESET}"
echo

# ---------- Step 11: Restart queues & bring panel online ----------
echo -e "${BLUE}→ Restarting queues and starting panel...${RESET}"
php artisan queue:restart
php artisan up
echo -e "${GREEN}✔ Panel is online.${RESET}"
echo

# ---------- Done ----------
echo -e "${BOLD}${GREEN}✅ Migration completed successfully!${RESET}"
