# Build and Deployment Guide

Quick reference for building and deploying the News Service.

## Prerequisites

**Local Development:**
- Python 3.11+
- PostgreSQL 12+ (optional, falls back to in-memory)

**Building Images:**
- Docker or Podman

**Deploying to OpenShift:**
- OpenShift CLI (`oc`)
- Access to OpenShift cluster
- Quay.io account (for image registry)

## Quick Start

### 1. Build and Push Image

**Linux/Mac:**
```bash
# Make executable
chmod +x build-and-push.sh

# Build and push to Quay.io
./build-and-push.sh
```

**Windows:**
```cmd
# Run batch file
build-and-push.bat
```

The script will:
- Ask for your Quay.io username (saves to `.quay-config`)
- Ask for version tag (default: `latest`)
- Build the Docker image
- Tag for Quay.io
- Login to Quay.io if needed
- Push image
- Optionally update `deployment.yaml`

**First time:**
- Enter Quay.io username when prompted
- Login when prompted: `docker login quay.io`
- Enter version (e.g., `1.0.0` or press Enter for `latest`)

**Subsequent builds:**
- Username is remembered from `.quay-config`
- Just specify version tag

### 2. Deploy to OpenShift

**Linux/Mac:**
```bash
# Make executable
chmod +x deploy.sh

# Deploy everything
./deploy.sh
```

**Windows:**
```cmd
# Run batch file
deploy.bat
```

The script will:
- Check OpenShift login
- Ask for project name
- Generate/reuse API key (saved to `.api-key`)
- Deploy PostgreSQL
- Initialize database
- Deploy news service
- Setup automated backups
- Display service URL and credentials

## Manual Build Steps

If you prefer manual control:

```bash
# Build image
docker build -t news-service:1.0.0 .

# Tag for Quay.io
docker tag news-service:1.0.0 quay.io/YOUR_USERNAME/news-service:1.0.0
docker tag news-service:1.0.0 quay.io/YOUR_USERNAME/news-service:latest

# Login to Quay.io
docker login quay.io

# Push
docker push quay.io/YOUR_USERNAME/news-service:1.0.0
docker push quay.io/YOUR_USERNAME/news-service:latest

# Update deployment
# Edit openshift/deployment.yaml and change the image line to:
# image: quay.io/YOUR_USERNAME/news-service:1.0.0
```

## Manual Deployment Steps

If you prefer manual control:

```bash
# Login to OpenShift
oc login <cluster-url>

# Create/select project
oc new-project news-service
# or
oc project news-service

# Deploy PostgreSQL
oc apply -f openshift/postgres-deployment.yaml

# Wait for PostgreSQL
oc wait --for=condition=available --timeout=120s deployment/postgres

# Initialize database
oc apply -f openshift/init-db-job.yaml
oc wait --for=condition=complete --timeout=60s job/news-service-init-db

# Create config and secrets
oc apply -f openshift/configmap.yaml

# Generate and set API key
API_KEY=$(python -c "import secrets; print(secrets.token_urlsafe(32))")
echo $API_KEY > .api-key
oc patch secret news-service-secrets -p "{\"stringData\":{\"API_KEY\":\"$API_KEY\"}}"

# Deploy application
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml

# Setup backups
oc apply -f openshift/backup-cronjob.yaml

# Get URL
oc get route news-service -o jsonpath='{.spec.host}'
```

## Version Management

### Semantic Versioning

Recommended versioning scheme:

- `1.0.0` - Major release
- `1.1.0` - Minor release (new features)
- `1.1.1` - Patch release (bug fixes)
- `latest` - Always points to latest build

### Example Workflow

```bash
# Initial release
./build-and-push.sh
# Enter version: 1.0.0

# Bug fix
./build-and-push.sh
# Enter version: 1.0.1

# New feature
./build-and-push.sh
# Enter version: 1.1.0

# Development build
./build-and-push.sh
# Enter version: dev
```

### Update Running Deployment

After pushing a new image:

```bash
# Option 1: Update and redeploy
./deploy.sh

# Option 2: Update image directly
oc set image deployment/news-service \
  news-service=quay.io/YOUR_USERNAME/news-service:1.1.0

# Option 3: Edit deployment
oc edit deployment news-service
# Change image line and save
```

## Local Development

### With Virtual Environment

```bash
# Create venv
python -m venv .venv

# Activate
# Windows:
.venv\Scripts\activate
# Linux/Mac:
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run locally (in-memory mode)
python app.py
```

### With PostgreSQL

```bash
# Start PostgreSQL (Docker)
docker run -d -p 5432:5432 \
  -e POSTGRES_USER=krisv \
  -e POSTGRES_PASSWORD=krisv \
  -e POSTGRES_DB=news \
  postgres:16-alpine

# Initialize schema
./init-db.sh

# Run app
python app.py
```

## Environment Variables

The app reads from `config.yaml` but can be overridden with environment variables:

```bash
# Database password
export DB_PASSWORD=krisv

# API key for POST /api/news
export API_KEY=your-secret-key

# Run app
python app.py
```

## Troubleshooting

### Build Issues

**Docker daemon not running:**
```bash
# Check status
docker info

# Start Docker Desktop (Windows/Mac)
# Or start Docker service (Linux)
sudo systemctl start docker
```

**Permission denied:**
```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER
# Then logout and login again
```

### Push Issues

**Authentication required:**
```bash
# Login to Quay.io
docker login quay.io

# Or use Podman
podman login quay.io
```

**Repository doesn't exist:**
1. Go to https://quay.io
2. Create repository: `news-service`
3. Set visibility (public or private)
4. Retry push

### Deployment Issues

**Not logged in to OpenShift:**
```bash
oc login <cluster-url>
```

**Insufficient permissions:**
```bash
# Check permissions
oc auth can-i create deployments

# Contact cluster admin if needed
```

**Image pull errors:**
```bash
# Check if image exists
docker pull quay.io/YOUR_USERNAME/news-service:latest

# Check if repository is public
# Or create image pull secret for private repos
```

## Files Reference

- `build-and-push.sh` - Automated build and push script
- `deploy.sh` - Automated deployment script
- `Dockerfile` - Container image definition
- `requirements.txt` - Python dependencies
- `.quay-config` - Saved Quay.io username (gitignored)
- `.api-key` - Saved API key (gitignored)
- `openshift/` - Kubernetes/OpenShift manifests

## CI/CD Integration

The scripts can be integrated into CI/CD pipelines:

**GitHub Actions example:**
```yaml
- name: Build and push
  run: |
    echo "${{ secrets.QUAY_USERNAME }}" > .quay-config
    echo "${{ secrets.QUAY_PASSWORD }}" | docker login quay.io -u $(cat .quay-config) --password-stdin
    ./build-and-push.sh <<EOF
    Y
    ${{ github.ref_name }}
    N
    EOF
```

**Jenkins example:**
```groovy
stage('Build') {
  sh './build-and-push.sh <<EOF\nY\n${env.BUILD_NUMBER}\nN\nEOF'
}
```

## Security Notes

- `.api-key` and `.quay-config` are gitignored
- Never commit these files to version control
- Use environment variables in CI/CD
- Rotate API keys regularly
- Use private repositories for production images

## Support

For issues or questions:
- Check logs: `oc logs -f deployment/news-service`
- View pods: `oc get pods`
- Describe resources: `oc describe deployment/news-service`
