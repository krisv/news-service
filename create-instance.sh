#!/bin/bash
# Create a new news service instance with isolated PostgreSQL
# Usage: ./create-instance.sh <instance-name> [service-port] [db-port]

set -e

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <instance-name> [service-port] [db-port]"
    echo ""
    echo "Example: $0 redhat-news 8080 5432"
    echo ""
    echo "This will create:"
    echo "  - Isolated PostgreSQL container on db-port (random if not specified)"
    echo "  - News service container on service-port (random if not specified)"
    echo "  - Config file: instances/<instance-name>/config.yaml"
    echo "  - Startup script: instances/<instance-name>/start.sh"
    echo "  - Shutdown script: instances/<instance-name>/stop.sh"
    exit 1
fi

INSTANCE_NAME="$1"

# Generate random ports if not provided
if [ -z "$2" ]; then
    SERVICE_PORT=$((8080 + RANDOM % 920))
else
    SERVICE_PORT="$2"
fi

if [ -z "$3" ]; then
    DB_PORT=$((15432 + RANDOM % 568))
else
    DB_PORT="$3"
fi

DB_USER="newsuser"
DB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))" 2>/dev/null || openssl rand -base64 16 | tr -d '\n')

# Create instance directory
INSTANCE_DIR="instances/$INSTANCE_NAME"
mkdir -p "$INSTANCE_DIR"

echo "========================================="
echo "Creating News Service Instance"
echo "========================================="
echo "Instance name: $INSTANCE_NAME"
echo "Service port: $SERVICE_PORT"
echo "Database port: $DB_PORT"
echo "Database user: $DB_USER"
echo ""

# Generate API key
API_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null || openssl rand -base64 32 | tr -d '\n')

# Create config file
echo "Creating config file..."
cat > "$INSTANCE_DIR/config.yaml" <<EOF
# News Service Configuration for $INSTANCE_NAME
# Auto-generated on $(date)

database:
  # PostgreSQL connection settings
  # Using host.docker.internal to reach host from container
  host: host.docker.internal
  port: $DB_PORT
  database: $INSTANCE_NAME
  username: $DB_USER
  password: $DB_PASSWORD

  # Connection pool settings
  min_connections: 1
  max_connections: 10

  # Retry settings
  connection_timeout: 5  # seconds
  max_retries: 3

security:
  # API key for POST endpoints (news creation and comments)
  api_key: "$API_KEY"
EOF
echo "✓ Config created: $INSTANCE_DIR/config.yaml"
echo ""

# Get absolute path to schema file
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/schema.sql"

# Create start script
echo "Creating start script..."
cat > "$INSTANCE_DIR/start.sh" <<'EOFSTART'
#!/bin/bash
# Start news service instance: INSTANCE_NAME_PLACEHOLDER
# Auto-generated on TIMESTAMP_PLACEHOLDER

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_CONTAINER="postgres-${INSTANCE_NAME}"
SERVICE_CONTAINER="news-service-${INSTANCE_NAME}"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"
DB_PORT="DB_PORT_PLACEHOLDER"
SERVICE_PORT="SERVICE_PORT_PLACEHOLDER"
DB_USER="DB_USER_PLACEHOLDER"
DB_PASSWORD="DB_PASSWORD_PLACEHOLDER"
SCHEMA_FILE="SCHEMA_FILE_PLACEHOLDER"

echo "========================================="
echo "Starting News Service: $INSTANCE_NAME"
echo "========================================="
echo ""

# Check if this is first run (volume doesn't exist)
FIRST_RUN=false
if ! docker volume inspect "$DB_VOLUME" > /dev/null 2>&1; then
    FIRST_RUN=true
    echo "Creating Docker volume: $DB_VOLUME"
    docker volume create "$DB_VOLUME"
fi

# Stop and remove existing containers if running
if docker ps -a --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "Stopping existing database container..."
    docker stop "$DB_CONTAINER" 2>/dev/null || true
    docker rm "$DB_CONTAINER" 2>/dev/null || true
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_CONTAINER}$"; then
    echo "Stopping existing service container..."
    docker stop "$SERVICE_CONTAINER" 2>/dev/null || true
    docker rm "$SERVICE_CONTAINER" 2>/dev/null || true
fi

# Start PostgreSQL container with Docker volume
echo "Starting PostgreSQL container..."
docker run -d \
    --name "$DB_CONTAINER" \
    -p "$DB_PORT:5432" \
    -v "$DB_VOLUME:/var/lib/postgresql/data" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_DB="$INSTANCE_NAME" \
    postgres:16-alpine

echo "✓ PostgreSQL container started on port $DB_PORT"
echo "✓ Data volume: $DB_VOLUME"
echo ""

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Error: PostgreSQL failed to start within 30 seconds"
        docker logs "$DB_CONTAINER"
        exit 1
    fi
    sleep 1
done
echo ""

# Initialize database schema (only on first run)
if [ "$FIRST_RUN" = true ]; then
    echo "First run detected - initializing database schema..."
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$INSTANCE_NAME" < "$SCHEMA_FILE"
    echo "✓ Schema initialized"
else
    echo "Using existing database data"
fi
echo ""

# Start news service container
echo "Starting news service container..."
docker run -d \
    --name "$SERVICE_CONTAINER" \
    --add-host host.docker.internal:host-gateway \
    -p "$SERVICE_PORT:8080" \
    -v "$SCRIPT_DIR/config.yaml:/app/config.yaml:ro" \
    -e API_KEY="$(<"$SCRIPT_DIR/config.yaml" grep 'api_key:' | awk '{print $2}' | tr -d '"')" \
    quay.io/krisv/news-service:latest

echo "✓ Service container started on port $SERVICE_PORT"
echo "✓ Using host.docker.internal to connect to database"
echo ""

echo "========================================="
echo "Instance Started Successfully!"
echo "========================================="
echo ""
echo "Service URL:  http://localhost:$SERVICE_PORT"
echo "Database:     localhost:$DB_PORT"
echo "API Key:      $(<"$SCRIPT_DIR/config.yaml" grep 'api_key:' | awk '{print $2}' | tr -d '"')"
echo ""
echo "Useful commands:"
echo "  Service logs:  docker logs -f $SERVICE_CONTAINER"
echo "  Database logs: docker logs -f $DB_CONTAINER"
echo "  Database CLI:  docker exec -it $DB_CONTAINER psql -U $DB_USER -d $INSTANCE_NAME"
echo "  Stop instance: $SCRIPT_DIR/stop.sh"
echo ""
EOFSTART

# Replace placeholders in start script
sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/start.sh"
sed -i "s/DB_PORT_PLACEHOLDER/$DB_PORT/g" "$INSTANCE_DIR/start.sh"
sed -i "s/SERVICE_PORT_PLACEHOLDER/$SERVICE_PORT/g" "$INSTANCE_DIR/start.sh"
sed -i "s|DB_USER_PLACEHOLDER|$DB_USER|g" "$INSTANCE_DIR/start.sh"
sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASSWORD|g" "$INSTANCE_DIR/start.sh"
sed -i "s|SCHEMA_FILE_PLACEHOLDER|$SCHEMA_FILE|g" "$INSTANCE_DIR/start.sh"
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$INSTANCE_DIR/start.sh"

chmod +x "$INSTANCE_DIR/start.sh"
echo "✓ Start script created: $INSTANCE_DIR/start.sh"
echo ""

# Create stop script
cat > "$INSTANCE_DIR/stop.sh" <<'EOFSTOP'
#!/bin/bash
# Stop news service instance: INSTANCE_NAME_PLACEHOLDER

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_CONTAINER="postgres-${INSTANCE_NAME}"
SERVICE_CONTAINER="news-service-${INSTANCE_NAME}"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"

echo "Stopping News Service: $INSTANCE_NAME"
echo ""

# Stop and remove service container
if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_CONTAINER}$"; then
    echo "Stopping service container..."
    docker stop "$SERVICE_CONTAINER" 2>/dev/null || true
    docker rm "$SERVICE_CONTAINER" 2>/dev/null || true
    echo "✓ Service container stopped"
else
    echo "⚠ Service container not found"
fi

# Stop and remove database container
if docker ps -a --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "Stopping database container..."
    docker stop "$DB_CONTAINER" 2>/dev/null || true
    docker rm "$DB_CONTAINER" 2>/dev/null || true
    echo "✓ Database container stopped"
else
    echo "⚠ Database container not found"
fi

echo ""
echo "✓ Instance stopped"
echo ""
echo "Database data is preserved in Docker volume: $DB_VOLUME"
echo "Restart with: $SCRIPT_DIR/start.sh"
echo "Delete data with: $SCRIPT_DIR/clean.sh"
EOFSTOP

sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/stop.sh"
chmod +x "$INSTANCE_DIR/stop.sh"
echo "✓ Stop script created: $INSTANCE_DIR/stop.sh"
echo ""

# Create status script
cat > "$INSTANCE_DIR/status.sh" <<'EOFSTATUS'
#!/bin/bash
# Check status of news service instance: INSTANCE_NAME_PLACEHOLDER

INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_CONTAINER="postgres-${INSTANCE_NAME}"
SERVICE_CONTAINER="news-service-${INSTANCE_NAME}"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"

echo "Instance Status: $INSTANCE_NAME"
echo "========================================="
echo ""

# Check database container
echo "Database Container ($DB_CONTAINER):"
if docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "  Status: ✓ Running"
    docker ps --format "  Port: {{.Ports}}" --filter "name=$DB_CONTAINER"
else
    echo "  Status: ✗ Not running"
fi
echo ""

# Check service container
echo "Service Container ($SERVICE_CONTAINER):"
if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_CONTAINER}$"; then
    echo "  Status: ✓ Running"
    docker ps --format "  Port: {{.Ports}}" --filter "name=$SERVICE_CONTAINER"
else
    echo "  Status: ✗ Not running"
fi
echo ""

# Check data volume
echo "Data Volume ($DB_VOLUME):"
if docker volume inspect "$DB_VOLUME" > /dev/null 2>&1; then
    echo "  Status: ✓ Exists"
    VOLUME_SIZE=$(docker system df -v --format 'table {{.Name}}\t{{.Size}}' 2>/dev/null | grep "$DB_VOLUME" | awk '{print $2}' || echo "unknown")
    if [ "$VOLUME_SIZE" != "unknown" ] && [ -n "$VOLUME_SIZE" ]; then
        echo "  Size: $VOLUME_SIZE"
    fi
else
    echo "  Status: ✗ Not found"
fi
echo ""
EOFSTATUS

sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/status.sh"
chmod +x "$INSTANCE_DIR/status.sh"
echo "✓ Status script created: $INSTANCE_DIR/status.sh"
echo ""

# Create clean script
cat > "$INSTANCE_DIR/clean.sh" <<'EOFCLEAN'
#!/bin/bash
# Clean/reset news service instance: INSTANCE_NAME_PLACEHOLDER
# WARNING: This will delete all database data!

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_CONTAINER="postgres-${INSTANCE_NAME}"
SERVICE_CONTAINER="news-service-${INSTANCE_NAME}"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"

echo "========================================="
echo "Clean Instance: $INSTANCE_NAME"
echo "========================================="
echo ""
echo "⚠️  WARNING: This will DELETE ALL DATA!"
echo ""
echo "Docker volume: $DB_VOLUME"
echo ""
read -p "Are you sure? Type 'yes' to continue: " -r
echo ""

if [ "$REPLY" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Stop containers first
echo "Stopping containers..."
"$SCRIPT_DIR/stop.sh"
echo ""

# Remove Docker volume
if docker volume inspect "$DB_VOLUME" > /dev/null 2>&1; then
    echo "Deleting Docker volume..."
    docker volume rm "$DB_VOLUME"
    echo "✓ Data deleted"
else
    echo "⚠ Docker volume not found"
fi

echo ""
echo "✓ Instance cleaned"
echo ""
echo "The instance has been reset to initial state."
echo "Run start.sh to create a fresh database."
EOFCLEAN

sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/clean.sh"
chmod +x "$INSTANCE_DIR/clean.sh"
echo "✓ Clean script created: $INSTANCE_DIR/clean.sh"
echo ""

# Create backup script
cat > "$INSTANCE_DIR/backup.sh" <<'EOFBACKUP'
#!/bin/bash
# Backup news service instance database: INSTANCE_NAME_PLACEHOLDER

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_CONTAINER="postgres-${INSTANCE_NAME}"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"
DB_USER="DB_USER_PLACEHOLDER"
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${INSTANCE_NAME}_${TIMESTAMP}.tar.gz"

echo "========================================="
echo "Backup Instance: $INSTANCE_NAME"
echo "========================================="
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "Error: Database container is not running"
    echo "Start it with: $SCRIPT_DIR/start.sh"
    exit 1
fi

# Check if volume exists
if ! docker volume inspect "$DB_VOLUME" > /dev/null 2>&1; then
    echo "Error: Docker volume $DB_VOLUME not found"
    exit 1
fi

echo "Backing up Docker volume: $DB_VOLUME"
echo "Backup file: $BACKUP_FILE"
echo ""

# Backup using a temporary container to tar the volume
docker run --rm \
    -v "$DB_VOLUME:/data:ro" \
    -v "$BACKUP_DIR:/backup" \
    alpine \
    tar -czf "/backup/$(basename "$BACKUP_FILE")" -C /data .

echo ""
echo "✓ Backup completed successfully!"
echo ""
echo "Backup file: $BACKUP_FILE"
echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo ""
echo "To restore this backup:"
echo "  1. Stop the instance: $SCRIPT_DIR/stop.sh"
echo "  2. Clean the data: $SCRIPT_DIR/clean.sh"
echo "  3. Restore: $SCRIPT_DIR/restore.sh $(basename "$BACKUP_FILE")"
EOFBACKUP

sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/backup.sh"
sed -i "s|DB_USER_PLACEHOLDER|$DB_USER|g" "$INSTANCE_DIR/backup.sh"
chmod +x "$INSTANCE_DIR/backup.sh"
echo "✓ Backup script created: $INSTANCE_DIR/backup.sh"
echo ""

# Create restore script
cat > "$INSTANCE_DIR/restore.sh" <<'EOFRESTORE'
#!/bin/bash
# Restore news service instance database: INSTANCE_NAME_PLACEHOLDER

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_NAME="INSTANCE_NAME_PLACEHOLDER"
DB_VOLUME="postgres-data-${INSTANCE_NAME}"
BACKUP_DIR="$SCRIPT_DIR/backups"

if [ -z "$1" ]; then
    echo "Usage: $0 <backup-file>"
    echo ""
    echo "Available backups:"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        ls -lh "$BACKUP_DIR"/*.tar.gz | awk '{print "  " $9 " (" $5 ")"}'
    else
        echo "  No backups found"
    fi
    exit 1
fi

BACKUP_FILE="$1"

# If just filename given, look in backups directory
if [ ! -f "$BACKUP_FILE" ]; then
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "========================================="
echo "Restore Instance: $INSTANCE_NAME"
echo "========================================="
echo ""
echo "⚠️  WARNING: This will REPLACE ALL CURRENT DATA!"
echo ""
echo "Backup file: $BACKUP_FILE"
echo ""
read -p "Are you sure? Type 'yes' to continue: " -r
echo ""

if [ "$REPLY" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Ensure containers are stopped
echo "Stopping containers..."
"$SCRIPT_DIR/stop.sh" 2>/dev/null || true
echo ""

# Remove existing volume if it exists
if docker volume inspect "$DB_VOLUME" > /dev/null 2>&1; then
    echo "Removing existing volume..."
    docker volume rm "$DB_VOLUME"
fi

# Create new volume
echo "Creating new volume..."
docker volume create "$DB_VOLUME"

# Restore backup to volume
echo "Restoring backup..."
docker run --rm \
    -v "$DB_VOLUME:/data" \
    -v "$(dirname "$BACKUP_FILE"):/backup:ro" \
    alpine \
    tar -xzf "/backup/$(basename "$BACKUP_FILE")" -C /data

echo ""
echo "✓ Restore completed successfully!"
echo ""
echo "Start the instance: $SCRIPT_DIR/start.sh"
EOFRESTORE

sed -i "s/INSTANCE_NAME_PLACEHOLDER/$INSTANCE_NAME/g" "$INSTANCE_DIR/restore.sh"
chmod +x "$INSTANCE_DIR/restore.sh"
echo "✓ Restore script created: $INSTANCE_DIR/restore.sh"
echo ""

echo "========================================="
echo "Instance Created Successfully!"
echo "========================================="
echo ""
echo "Instance: $INSTANCE_NAME"
echo "Location: $INSTANCE_DIR"
echo ""
echo "Ports:"
echo "  Service: $SERVICE_PORT"
echo "  Database: $DB_PORT"
echo ""
echo "API Key: $API_KEY"
echo ""
echo "Data persistence:"
echo "  Docker volume: postgres-data-$INSTANCE_NAME"
echo "  Data survives container restarts and removals"
echo ""
echo "Management scripts:"
echo "  start.sh   - Start database and service"
echo "  stop.sh    - Stop containers (data preserved in Docker volume)"
echo "  status.sh  - Check containers and volume status"
echo "  clean.sh   - Delete all data and reset"
echo "  backup.sh  - Backup database to file"
echo ""
echo "Next steps:"
echo "  1. Start instance: $INSTANCE_DIR/start.sh"
echo "  2. Access at:      http://localhost:$SERVICE_PORT"
echo ""
