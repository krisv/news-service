#!/bin/bash
# Restore PostgreSQL backup from local machine to OpenShift

set -e

if [ -z "$1" ]; then
    echo "Usage: ./backup-restore.sh <backup-file>"
    echo ""
    echo "Example: ./backup-restore.sh backups/news-backup-20260415-143022.sql.gz"
    echo ""
    echo "Available backups:"
    if ls backups/*.sql.gz 1> /dev/null 2>&1; then
        ls -lh backups/*.sql.gz
    else
        echo "  No backups found in backups/ directory"
    fi
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "X Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "+ Restoring database backup to OpenShift..."
echo "  Backup file: $BACKUP_FILE"
echo ""

# Get the PostgreSQL pod name
echo "+ Finding PostgreSQL pod..."
POSTGRES_POD=$(oc get pods -l app=news-service-db -o jsonpath="{.items[0].metadata.name}")

if [ -z "$POSTGRES_POD" ]; then
    echo "X Error: Could not find PostgreSQL pod"
    echo "  Make sure the pod is running: oc get pods"
    exit 1
fi

echo "  Found pod: $POSTGRES_POD"
echo ""

# Confirm with user
echo "! WARNING: This will DELETE all existing data and replace it with the backup!"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "  Restore cancelled."
    exit 0
fi

echo ""
echo "+ Uploading backup to server..."
oc cp "$BACKUP_FILE" $POSTGRES_POD:/tmp/restore.sql.gz

echo "+ Terminating active database connections..."
oc exec $POSTGRES_POD -- psql -U krisv postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'news' AND pid <> pg_backend_pid();"

echo "+ Dropping existing database..."
oc exec $POSTGRES_POD -- dropdb -U krisv --if-exists news

echo "+ Creating fresh database..."
oc exec $POSTGRES_POD -- createdb -U krisv news

echo "+ Restoring backup..."
oc exec $POSTGRES_POD -- bash -c "gunzip < /tmp/restore.sql.gz | psql -U krisv news"

echo "+ Cleaning up temporary file..."
oc exec $POSTGRES_POD -- rm /tmp/restore.sql.gz

echo ""
echo "+ Restore completed successfully!"
echo "  Database has been restored from: $BACKUP_FILE"
echo ""
echo "  You may want to restart the news-service pod to refresh connections:"
echo "  oc delete pod -l app=news-service"
