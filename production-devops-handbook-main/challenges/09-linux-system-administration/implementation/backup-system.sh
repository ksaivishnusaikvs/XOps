#!/bin/bash
#
# System Backup Script using Restic
# Performs full system backup with encryption to local or cloud storage
#
# Usage: sudo ./backup-system.sh
#

set -euo pipefail

# Configuration
BACKUP_NAME="system-backup-$(hostname)"
BACKUP_PATHS=(
    "/etc"
    "/home"
    "/root"
    "/var/www"
    "/opt"
)

EXCLUDE_PATHS=(
    "/home/*/.cache"
    "/home/*/Downloads"
    "*.tmp"
    "*.temp"
    "/var/cache"
    "/var/tmp"
)

# Database backup directory
DB_BACKUP_DIR="/var/backups/databases"
mkdir -p "$DB_BACKUP_DIR"

# Load configuration from environment file
CONFIG_FILE="/etc/restic/backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file $CONFIG_FILE not found"
    echo "Creating example configuration..."
    
    mkdir -p /etc/restic
    cat > "$CONFIG_FILE" <<'EOF'
# Restic Backup Configuration

# Repository location (local path or S3)
# Local: /backup/repo
# S3: s3:s3.amazonaws.com/my-backup-bucket
export RESTIC_REPOSITORY="/backup/repo"

# Repository password (use strong password)
export RESTIC_PASSWORD="CHANGE-THIS-STRONG-PASSWORD"

# For S3 repositories
#export AWS_ACCESS_KEY_ID="your-access-key"
#export AWS_SECRET_ACCESS_KEY="your-secret-key"

# Retention policy
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=2

# Notification settings
NOTIFY_EMAIL="admin@example.com"
NOTIFY_ON_SUCCESS=false
NOTIFY_ON_FAILURE=true
EOF
    
    echo "Please edit $CONFIG_FILE with your settings"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Send notification
send_notification() {
    local subject="$1"
    local message="$2"
    
    if command -v mail &> /dev/null && [[ -n "$NOTIFY_EMAIL" ]]; then
        echo "$message" | mail -s "$subject" "$NOTIFY_EMAIL"
    else
        warning "Mail command not available, skipping notification"
    fi
}

# Check if restic is installed
if ! command -v restic &> /dev/null; then
    error "Restic is not installed. Please install it first."
    exit 1
fi

# Check if repository is initialized
if ! restic snapshots &> /dev/null; then
    error "Restic repository not initialized or credentials incorrect"
    exit 1
fi

log "Starting system backup: $BACKUP_NAME"

# Backup databases
log "Backing up databases..."

# MySQL/MariaDB
if command -v mysqldump &> /dev/null; then
    log "Backing up MySQL databases..."
    
    MYSQL_BACKUP="$DB_BACKUP_DIR/mysql-$(date +%F-%H%M%S).sql.gz"
    
    # Get list of databases
    mysql -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|sys)" | while read db; do
        mysqldump --single-transaction --routines --triggers "$db" | gzip >> "$MYSQL_BACKUP"
    done
    
    log "MySQL backup saved to $MYSQL_BACKUP"
fi

# PostgreSQL
if command -v pg_dumpall &> /dev/null; then
    log "Backing up PostgreSQL databases..."
    
    POSTGRES_BACKUP="$DB_BACKUP_DIR/postgres-$(date +%F-%H%M%S).sql.gz"
    sudo -u postgres pg_dumpall | gzip > "$POSTGRES_BACKUP"
    
    log "PostgreSQL backup saved to $POSTGRES_BACKUP"
fi

# MongoDB
if command -v mongodump &> /dev/null; then
    log "Backing up MongoDB databases..."
    
    MONGO_BACKUP_DIR="$DB_BACKUP_DIR/mongodb-$(date +%F-%H%M%S)"
    mongodump --out="$MONGO_BACKUP_DIR"
    tar -czf "${MONGO_BACKUP_DIR}.tar.gz" -C "$DB_BACKUP_DIR" "$(basename $MONGO_BACKUP_DIR)"
    rm -rf "$MONGO_BACKUP_DIR"
    
    log "MongoDB backup saved to ${MONGO_BACKUP_DIR}.tar.gz"
fi

# Add database backup directory to backup paths
BACKUP_PATHS+=("$DB_BACKUP_DIR")

# Build exclude arguments
EXCLUDE_ARGS=()
for exclude in "${EXCLUDE_PATHS[@]}"; do
    EXCLUDE_ARGS+=(--exclude "$exclude")
done

# Perform backup
log "Performing restic backup..."

START_TIME=$(date +%s)

if restic backup \
    --tag "system" \
    --tag "$(hostname)" \
    "${EXCLUDE_ARGS[@]}" \
    "${BACKUP_PATHS[@]}" \
    --verbose; then
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log "Backup completed successfully in ${DURATION}s"
    
    # Verify backup
    log "Verifying backup integrity..."
    if restic check --read-data-subset=5%; then
        log "Backup verification passed"
    else
        error "Backup verification failed!"
        send_notification "Backup Verification Failed: $BACKUP_NAME" \
            "Backup completed but verification failed. Please investigate."
        exit 1
    fi
    
    # Apply retention policy
    log "Applying retention policy..."
    restic forget \
        --keep-daily "$KEEP_DAILY" \
        --keep-weekly "$KEEP_WEEKLY" \
        --keep-monthly "$KEEP_MONTHLY" \
        --keep-yearly "$KEEP_YEARLY" \
        --prune
    
    # Get backup statistics
    SNAPSHOT_ID=$(restic snapshots --latest 1 --json | grep -o '"short_id":"[^"]*' | cut -d'"' -f4)
    BACKUP_SIZE=$(restic stats latest --json | grep -o '"total_size":[0-9]*' | cut -d':' -f2)
    BACKUP_SIZE_MB=$((BACKUP_SIZE / 1024 / 1024))
    
    # Generate report
    REPORT="
Backup Report
=============
Hostname: $(hostname)
Date: $(date)
Duration: ${DURATION}s
Snapshot ID: $SNAPSHOT_ID
Backup Size: ${BACKUP_SIZE_MB} MB

Backed up paths:
$(printf '%s\n' "${BACKUP_PATHS[@]}")

Retention Policy:
- Daily: $KEEP_DAILY
- Weekly: $KEEP_WEEKLY
- Monthly: $KEEP_MONTHLY
- Yearly: $KEEP_YEARLY

Status: SUCCESS
"
    
    log "$REPORT"
    
    # Save report
    echo "$REPORT" > "/var/log/backup-$(date +%F).log"
    
    # Send notification
    if [[ "$NOTIFY_ON_SUCCESS" == "true" ]]; then
        send_notification "Backup Success: $BACKUP_NAME" "$REPORT"
    fi
    
else
    error "Backup failed!"
    
    FAILURE_REPORT="
Backup Failure Report
====================
Hostname: $(hostname)
Date: $(date)

Backup failed to complete. Please check system logs for details.

Status: FAILED
"
    
    log "$FAILURE_REPORT"
    
    if [[ "$NOTIFY_ON_FAILURE" == "true" ]]; then
        send_notification "Backup Failed: $BACKUP_NAME" "$FAILURE_REPORT"
    fi
    
    exit 1
fi

# Clean up old database backups (keep last 7 days)
log "Cleaning up old database backups..."
find "$DB_BACKUP_DIR" -type f -mtime +7 -delete

log "Backup process completed"

exit 0
