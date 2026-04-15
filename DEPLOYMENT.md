# OpenShift Deployment Guide

Complete guide for deploying the news service to OpenShift with PostgreSQL.

## Prerequisites

- OpenShift CLI (`oc`) installed
- Access to an OpenShift cluster
- Docker/Podman for building images

## Quick Start

```bash
# 1. Login to OpenShift
oc login <your-cluster-url>

# 2. Create project
oc new-project news-service

# 3. Deploy PostgreSQL
oc apply -f openshift/postgres-deployment.yaml

# 4. Initialize database
oc apply -f openshift/init-db-job.yaml

# 5. Create ConfigMap and Secrets
oc apply -f openshift/configmap.yaml

# 6. Update API key in secret
oc patch secret news-service-secrets -p '{"stringData":{"API_KEY":"'$(python -c "import secrets; print(secrets.token_urlsafe(32))")'"}}' 

# 7. Deploy news service
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml

# 8. Setup automated backups
oc apply -f openshift/backup-cronjob.yaml
```

## Deployment Steps (Detailed)

### 1. PostgreSQL Database

Deploy PostgreSQL with persistent storage:

```bash
oc apply -f openshift/postgres-deployment.yaml
```

This creates:
- **PersistentVolumeClaim** (5Gi) for database data
- **Secret** with database credentials
- **Deployment** running Postgres 16
- **Service** exposing port 5432

**Default credentials:**
- Username: `newsadmin`
- Password: `changeme123`
- Database: `news`

**Update credentials:**
```bash
oc patch secret postgres-credentials -p '{"stringData":{"POSTGRES_PASSWORD":"your-new-password"}}'
```

### 2. Initialize Database Schema

Run the init job to create tables:

```bash
oc apply -f openshift/init-db-job.yaml
```

Check job status:
```bash
oc logs job/news-service-init-db
```

The job will:
- Wait for PostgreSQL to be ready
- Create tables (news_items, comments)
- Add indexes
- Insert default news items
- Skip initialization if tables already exist

### 3. Configure News Service

Generate a secure API key:
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Update the secret:
```bash
# Edit openshift/configmap.yaml and replace REPLACE_WITH_SECURE_KEY
# Then apply:
oc apply -f openshift/configmap.yaml

# Or patch directly:
oc patch secret news-service-secrets -p '{"stringData":{"API_KEY":"your-generated-key"}}'
```

### 4. Build and Push Image

```bash
# Build image
docker build -t news-service:latest .

# Tag for registry
docker tag news-service:latest quay.io/YOUR_USERNAME/news-service:1.0.0

# Push to registry
docker push quay.io/YOUR_USERNAME/news-service:1.0.0
```

Update `openshift/deployment.yaml` with your image:
```yaml
image: quay.io/YOUR_USERNAME/news-service:1.0.0
```

### 5. Deploy News Service

```bash
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml
```

Get the route URL:
```bash
oc get route news-service -o jsonpath='{.spec.host}'
```

### 6. Setup Automated Backups

Deploy the backup CronJob:

```bash
oc apply -f openshift/backup-cronjob.yaml
```

This runs daily at 2 AM and:
- Creates compressed SQL dumps
- Stores in separate PVC (10Gi)
- Keeps last 7 days of backups

**Manual backup:**
```bash
oc create job --from=cronjob/postgres-backup manual-backup-$(date +%s)
```

**List backups:**
```bash
oc exec deployment/postgres -- ls -lh /backups
```

## Backup & Restore

### Restore from Backup

1. Edit `openshift/restore-job.yaml` and set the backup filename:
   ```yaml
   - name: BACKUP_FILE
     value: "news-backup-20260415-020000.sql.gz"
   ```

2. Run the restore job:
   ```bash
   oc apply -f openshift/restore-job.yaml
   ```

3. Check logs:
   ```bash
   oc logs job/postgres-restore
   ```

**⚠️ Warning:** Restore drops the existing database!

### Download Backup

```bash
oc rsync postgres-<pod-id>:/backups ./local-backups
```

## Configuration

### Environment Variables

The app reads from `config.yaml` but can override with environment variables:

- `DB_PASSWORD` - PostgreSQL password
- `API_KEY` - API key for POST /api/news

Set in `openshift/configmap.yaml` secret.

### Database Connection

Connection details in ConfigMap:
```yaml
database:
  host: postgres       # Service name
  port: 5432
  database: news
  username: newsadmin
```

## Security

### API Key Authentication

**Protected endpoints:**
- `POST /api/news` - Requires `X-API-Key` header

**Open endpoints:**
- `GET /api/news` - Public
- `POST /api/news/{id}/comments` - Public
- All other GET endpoints - Public

**Using the API key:**
```bash
curl -X POST https://your-route/api/news \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"title":"News Title","content":"Content","labels":["topic:AI"]}'
```

### Disable API Key

Leave empty in config:
```yaml
security:
  api_key: ""
```

## Troubleshooting

### Check Pod Status
```bash
oc get pods -l app=news-service
oc logs -l app=news-service
```

### Database Connection Issues
```bash
# Check postgres is running
oc get pods -l app=news-service-db

# Test connection
oc exec deployment/postgres -- psql -U newsadmin -d news -c "SELECT 1"

# Check service
oc get svc postgres
```

### View Logs
```bash
# News service logs
oc logs -f deployment/news-service

# Postgres logs
oc logs -f deployment/postgres

# Backup job logs
oc logs job/postgres-backup-<timestamp>
```

### Restart Services
```bash
# Restart app
oc rollout restart deployment/news-service

# Restart database (careful!)
oc rollout restart deployment/postgres
```

## Scaling

### Scale Application
```bash
# Scale to 3 replicas
oc scale deployment/news-service --replicas=3
```

**Note:** PostgreSQL stays at 1 replica (stateful)

### Increase Storage
```bash
# Edit PVC
oc edit pvc postgres-data

# Change storage size, e.g.:
spec:
  resources:
    requests:
      storage: 10Gi
```

## Monitoring

### Resource Usage
```bash
oc adm top pods
```

### Database Size
```bash
oc exec deployment/postgres -- psql -U newsadmin -d news -c "
  SELECT pg_size_pretty(pg_database_size('news'))
"
```

### Table Counts
```bash
oc exec deployment/postgres -- psql -U newsadmin -d news -c "
  SELECT 
    (SELECT COUNT(*) FROM news_items) as news_items,
    (SELECT COUNT(*) FROM comments) as comments
"
```

## Cleanup

Remove everything:
```bash
oc delete all -l app=news-service
oc delete all -l app=news-service-db
oc delete pvc postgres-data postgres-backups
oc delete secret postgres-credentials news-service-secrets
oc delete configmap news-service-config
```

## Files Reference

- `postgres-deployment.yaml` - PostgreSQL deployment with PVC
- `configmap.yaml` - App configuration and secrets
- `deployment.yaml` - News service deployment
- `service.yaml` - ClusterIP service
- `route.yaml` - External route
- `init-db-job.yaml` - Database initialization job
- `backup-cronjob.yaml` - Automated daily backups
- `restore-job.yaml` - Restore from backup template
