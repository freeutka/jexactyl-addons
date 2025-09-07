#!/bin/bash
set -euo pipefail

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# ---------- Default values ----------
DIR="/var/www/jexactyl"
DB_NAME="panel"
DB_USER=""
DB_PASS=""
DB_HOST="localhost"
SKIP_BACKUP=false
AUTO_CONFIRM=false

# ---------- Usage function ----------
usage() {
    echo -e "${BOLD}Usage:${RESET} $0 [OPTIONS]"
    echo
    echo -e "${BOLD}Options:${RESET}"
    echo "  -d, --dir DIR          Working directory (default: /var/www/jexactyl)"
    echo "  -n, --dbname NAME      Database name (default: panel)"
    echo "  -u, --dbuser USER      Database username"
    echo "  -p, --dbpass PASS      Database password"
    echo "  -h, --dbhost HOST      Database host (default: localhost)"
    echo "  -s, --skip-backup      Skip backup creation"
    echo "  -y, --yes              Auto-confirm all prompts"
    echo "  --help                 Show this help message"
    echo
    echo -e "${BOLD}Examples:${RESET}"
    echo "  $0 --dbname jexuser --dbpass 123"
    echo "  $0 -d /var/www/pterodactyl -n panel -u root -p password123"
    echo "  $0 --skip-backup --yes"
    exit 1
}

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            DIR="$2"
            shift 2
            ;;
        -n|--dbname)
            DB_NAME="$2"
            shift 2
            ;;
        -u|--dbuser)
            DB_USER="$2"
            shift 2
            ;;
        -p|--dbpass)
            DB_PASS="$2"
            shift 2
            ;;
        -h|--dbhost)
            DB_HOST="$2"
            shift 2
            ;;
        -s|--skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            usage
            ;;
    esac
done

# ---------- Header ----------
echo -e "${BOLD}${BLUE}=== Jexactyl v3 → Jexpanel v4 Migration Script ===${RESET}"
echo

# ---------- Validate database credentials ----------
if [[ -z "$DB_USER" ]]; then
    read -rp "Database username: " DB_USER
fi

if [[ -z "$DB_PASS" ]]; then
    read -rsp "Database password: " DB_PASS
    echo
fi

# ---------- Test database connection ----------
echo -e "${BLUE}→ Testing database connection...${RESET}"
if ! mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "USE $DB_NAME" &>/dev/null; then
    echo -e "${RED}✗ Database connection failed!${RESET}"
    exit 1
fi
echo -e "${GREEN}✔ Database connection successful.${RESET}"
echo

# ---------- Step 1: Choose directory ----------
if [[ "$AUTO_CONFIRM" == false ]]; then
    echo -e "${BOLD}Choose the working directory:${RESET}"
    echo "1) /var/www/jexactyl"
    echo "2) /var/www/pterodactyl"
    echo "3) Custom: $DIR"
    read -rp "> " choice

    if [[ "$choice" == "2" ]]; then
        DIR="/var/www/pterodactyl"
    elif [[ "$choice" == "1" ]]; then
        DIR="/var/www/jexactyl"
    fi
fi

echo -e "${BLUE}→ Working directory set to:${RESET} $DIR"
echo

cd "$DIR"

# ---------- Step 2: Backup ----------
if [[ "$SKIP_BACKUP" == false ]]; then
    if [[ "$AUTO_CONFIRM" == true ]] || { read -rp "Do you want to create a backup? (y/n): " backup && [[ "$backup" =~ ^[Yy]$ ]]; }; then
        echo -e "${BLUE}→ Creating backup...${RESET}"
        cp -R "$DIR" "${DIR}-backup"
        mysqldump -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" > "${DIR}/backup.sql"
        echo -e "${GREEN}✔ Backup created at ${DIR}-backup and ${DIR}/backup.sql${RESET}"
    else
        echo -e "${YELLOW}⚠ Backup skipped.${RESET}"
    fi
else
    echo -e "${YELLOW}⚠ Backup skipped (--skip-backup).${RESET}"
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
mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" <<EOF
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
    chown -R nginx:nginx "$DIR"/*
elif id "apache" &>/dev/null; then
    chown -R apache:apache "$DIR"/*
else
    chown -R www-data:www-data "$DIR"/*
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
