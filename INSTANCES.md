# News Service Instances

This document explains how to create and manage multiple isolated instances of the news service.

## Overview

Each instance includes:
- **Isolated PostgreSQL container** - dedicated database on its own port
- **News service container** - separate service on its own port
- **Persistent data storage** - database data stored in Docker volume
- **Auto-generated credentials** - unique API key and database password
- **Management scripts** - start, stop, status, clean, backup, and restore scripts

## Quick Start

Create and start a new instance:

```bash
./create-instance.sh my-news-instance
./instances/my-news-instance/start.sh
```

## Prerequisites

- **Docker** must be installed and running
- **Image available**: `quay.io/krisv/news-service:latest`
  - Build with: `./build-and-push.sh`

**No PostgreSQL installation required** - each instance runs its own containerized database.

## Usage

### Create Instance

```bash
./create-instance.sh <instance-name> [service-port] [db-port]
```

**Arguments:**
- `instance-name` (required): Name for the instance
- `service-port` (optional): Port for the web service (random 8080-8999 if not specified)
- `db-port` (optional): Port for PostgreSQL (random 15432-15999 if not specified)

**Examples:**

Basic instance with random ports:
```bash
./create-instance.sh redhat-news
```

Specific ports:
```bash
./create-instance.sh customer-news 8080 15432
```

Multiple instances:
```bash
./create-instance.sh news1 8080 15432
./create-instance.sh news2 8081 15433
./create-instance.sh news3 8082 15434
```

### Start Instance

```bash
./instances/<instance-name>/start.sh
```

This will:
1. Create a Docker volume (first run only)
2. Stop and remove any existing containers for this instance
3. Start a new PostgreSQL container with persistent volume
4. Wait for PostgreSQL to be ready
5. Initialize the database schema (first run only)
6. Start the news service container

The script shows you the service URL, database connection, and API key.

### Stop Instance

```bash
./instances/<instance-name>/stop.sh
```

This stops and removes both the service and database containers.

**✓ Data is preserved:** Database data remains in the Docker volume and will be restored when you start again.

### Check Status

```bash
./instances/<instance-name>/status.sh
```

Shows whether the database and service containers are running.

### View Logs

Service logs:
```bash
docker logs -f news-service-<instance-name>
```

Database logs:
```bash
docker logs -f postgres-<instance-name>
```

### Access Database

Connect to the database CLI:
```bash
docker exec -it postgres-<instance-name> psql -U newsuser -d <instance-name>
```

## Instance Directory Structure

```
instances/
└── <instance-name>/
    ├── config.yaml      # Database and security config
    ├── backups/         # Database backups (created by backup.sh)
    ├── start.sh         # Start both database and service
    ├── stop.sh          # Stop containers (data preserved)
    ├── status.sh        # Check containers and volume status
    ├── clean.sh         # Delete all data and reset
    ├── backup.sh        # Backup database to file
    └── restore.sh       # Restore database from backup
```

Note: Database data is stored in a Docker volume named `postgres-data-<instance-name>`, not in the instance directory.

## Configuration

Each instance has its own `config.yaml` with:
- Database connection settings (pointing to localhost:db-port)
- Auto-generated database password
- Auto-generated API key for authentication
- Connection pool and retry settings

Edit `instances/<instance-name>/config.yaml` to customize, but you'll need to restart for changes to take effect.

## Accessing Instances

**Web UI:**
```
http://localhost:<service-port>
```

**API Endpoints:**
See main README.md for API documentation.

**Authentication:**
Include the API key (from config.yaml) in request headers:
```bash
curl -H "X-API-Key: <your-key>" http://localhost:8080/api/news
```

## Data Persistence

**Database data is automatically persisted** in a Docker volume named `postgres-data-<instance-name>`.

### How it works:
- First time you run `start.sh`: Creates Docker volume, initializes database and schema
- Subsequent runs: Reuses existing data from Docker volume
- Run `stop.sh`: Containers removed, but data preserved in Docker volume
- Run `start.sh` again: Data is restored from volume

### Why Docker volumes?
Docker volumes avoid file permission issues on Windows/WSL and provide better performance than bind mounts. Docker manages the storage internally.

### View volumes:

```bash
# List all volumes
docker volume ls | grep postgres-data

# Inspect a specific volume
docker volume inspect postgres-data-<instance-name>
```

### Reset to fresh state:

```bash
./instances/<instance-name>/clean.sh
```

This will:
1. Stop all containers
2. Delete the Docker volume
3. Next `start.sh` will create a fresh database

### Backup and restore:

Use the provided scripts:

```bash
# Create a backup
./instances/<instance-name>/backup.sh
# Creates: instances/<instance-name>/backups/<instance-name>_YYYYMMDD_HHMMSS.tar.gz

# List available backups
./instances/<instance-name>/restore.sh
# Shows all available backup files

# Restore from backup
./instances/<instance-name>/restore.sh <backup-file>
# Example: ./instances/my-instance/restore.sh my-instance_20260419_143022.tar.gz
```

Backups are stored as `.tar.gz` files in the `backups/` directory and can be copied/moved for safekeeping.

## Container and Volume Names

Each instance creates:

**Containers:**
- `postgres-<instance-name>` - PostgreSQL database
- `news-service-<instance-name>` - News service application

**Volumes:**
- `postgres-data-<instance-name>` - Persistent database storage

## Port Conflicts

If you get a port conflict:

```bash
# List what's using the port
netstat -an | grep <port>

# or on Linux/Mac
lsof -i :<port>

# Create instance with different ports
./create-instance.sh myinstance 8085 15435
```

## Troubleshooting

**Container fails to start:**
```bash
# Check Docker is running
docker ps

# View container logs
docker logs news-service-<instance-name>
docker logs postgres-<instance-name>

# Check port availability
netstat -an | grep <port>
```

**Database connection errors:**
```bash
# Check if PostgreSQL container is running
docker ps | grep postgres-<instance-name>

# Check database logs
docker logs postgres-<instance-name>

# Verify database is ready
docker exec postgres-<instance-name> pg_isready -U newsuser
```

**Schema not initialized:**
```bash
# Manually initialize schema
docker exec -i postgres-<instance-name> psql -U newsuser -d <instance-name> < schema.sql
```

**Image not found:**
```bash
# Check if image exists
docker images | grep news-service

# Build the image
./build-and-push.sh
```

## Cleaning Up

### Reset instance data (keep config):

```bash
./instances/<instance-name>/clean.sh
```

This deletes all database data but keeps the instance configuration.

### Remove instance completely:

```bash
# Stop containers
./instances/<instance-name>/stop.sh

# Remove entire instance directory (including all data)
rm -rf instances/<instance-name>
```

### Remove all stopped containers:
```bash
docker container prune
```

## Advanced: Network Configuration

By default, the service connects to the database via `localhost:<db-port>`. This works because both containers publish ports to the host.

For more isolated networking, you could modify the scripts to:
1. Create a Docker network per instance
2. Use container names instead of localhost
3. Only expose the service port, not the database port

## Multiple Instances Example

Run three isolated instances:

```bash
# Create instances
./create-instance.sh redhat-news 8080 15432
./create-instance.sh customer-news 8081 15433
./create-instance.sh internal-news 8082 15434

# Start all
./instances/redhat-news/start.sh
./instances/customer-news/start.sh
./instances/internal-news/start.sh

# Check status
./instances/redhat-news/status.sh
./instances/customer-news/status.sh
./instances/internal-news/status.sh

# Access
open http://localhost:8080  # redhat-news
open http://localhost:8081  # customer-news
open http://localhost:8082  # internal-news
```

## Security Notes

- Each instance has a unique API key and database password
- Credentials are stored in `config.yaml` (excluded from git)
- Database ports are exposed on localhost only
- For production, consider:
  - Using Docker secrets
  - Running behind a reverse proxy
  - Enabling TLS
  - Using Docker networks instead of host ports
