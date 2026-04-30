# News Service Instances

This directory contains individual news service instance configurations.
Each instance is created using the `create-instance.sh` script.

## Quick Start

```bash
# Create an instance (from parent directory)
cd ..
./create-instance.sh my-instance

# Start it
./instances/my-instance/start.sh

# Access at http://localhost:<port>
```

## What's in an instance directory?

Each instance directory contains:
- `config.yaml` - Database connection and API key configuration
- `backups/` - Database backup files (created by backup.sh)
- `start.sh` - Starts both PostgreSQL and service containers
- `stop.sh` - Stops containers (data preserved in Docker volume)
- `status.sh` - Shows container and volume status
- `clean.sh` - Deletes all data and resets instance
- `backup.sh` - Creates a backup of the database
- `restore.sh` - Restores database from a backup file

Note: Database data is stored in a Docker volume, not in this directory.

## Instance Isolation

Each instance is completely isolated with:
- Its own PostgreSQL container on a unique port
- Its own news service container on a unique port  
- Its own Docker volume for persistent data storage
- Its own database with independent data
- Its own API key for authentication

## Data Persistence

Database data is automatically saved in a Docker volume (`postgres-data-<instance-name>`) and survives:
- Container stops and restarts
- Container removals
- Docker daemon restarts
- System reboots

The data is managed by Docker internally, avoiding file permission issues on Windows/WSL.

To reset an instance to a fresh state, use `clean.sh` (deletes the Docker volume).
To backup data, use `backup.sh` (creates a .tar.gz file in the backups/ directory).

## Learn More

See `../INSTANCES.md` for full documentation.
