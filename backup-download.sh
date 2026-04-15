#!/bin/bash
# Download PostgreSQL backup from OpenShift to local machine

set -e

echo "+ Downloading database backup from OpenShift..."
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

# Create backup directory locally if it doesn't exist
mkdir -p backups

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="backups/news-backup-$TIMESTAMP.sql.gz"

echo "+ Creating backup on server..."
oc exec $POSTGRES_POD -- bash -c "pg_dump -U krisv news | gzip > /tmp/backup.sql.gz"

echo "+ Downloading backup to local machine..."
oc cp $POSTGRES_POD:/tmp/backup.sql.gz $BACKUP_FILE

echo "+ Cleaning up temporary file..."
oc exec $POSTGRES_POD -- rm /tmp/backup.sql.gz

echo ""
echo "+ Backup completed successfully!"
echo "  File: $BACKUP_FILE"
ls -lh $BACKUP_FILE
echo ""
echo "  To restore this backup, run: ./backup-restore.sh $BACKUP_FILE"
