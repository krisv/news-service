#!/bin/bash
# Initialize PostgreSQL database with schema
# This script can be run manually or as a Kubernetes Job

set -e

# Database connection details (from environment or defaults)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-news}"
DB_USER="${DB_USER:-krisv}"
PGPASSWORD="${DB_PASSWORD:-krisv}"

export PGPASSWORD

echo "Initializing database: $DB_NAME"
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo ""

# Check if PostgreSQL is running
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" > /dev/null 2>&1; then
    echo "Error: PostgreSQL is not running at $DB_HOST:$DB_PORT"
    echo ""
    echo "For OpenShift deployment:"
    echo "  oc apply -f openshift/postgres-deployment.yaml"
    echo ""
    echo "For local Docker:"
    echo "  docker run -d -p 5432:5432 \\"
    echo "    -e POSTGRES_USER=krisv \\"
    echo "    -e POSTGRES_PASSWORD=krisv \\"
    echo "    -e POSTGRES_DB=news \\"
    echo "    postgres:16-alpine"
    exit 1
fi

# Apply schema
echo "Applying schema.sql..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$(dirname "$0")/schema.sql"

echo ""
echo "✓ Database initialized successfully!"
echo ""
echo "Connection details for config.yaml:"
echo "  host: $DB_HOST"
echo "  port: $DB_PORT"
echo "  database: $DB_NAME"
echo "  username: $DB_USER"
