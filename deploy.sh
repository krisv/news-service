#!/bin/bash
# OpenShift Deployment Script for News Service
# Automates deployment of PostgreSQL + News Service

set -e

echo "=========================================="
echo "News Service - OpenShift Deployment"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# API key file
API_KEY_FILE=".api-key"

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ Error: oc (OpenShift CLI) is not installed${NC}"
    echo "Install from: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
    exit 1
fi

# Check if logged in
echo -e "${CYAN}Checking OpenShift login status...${NC}"
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Error: Not logged in to OpenShift${NC}"
    echo "Please login first with: oc login <cluster-url>"
    exit 1
fi

CURRENT_USER=$(oc whoami)
CURRENT_SERVER=$(oc whoami --show-server)
echo -e "${GREEN}✓ Logged in as: ${CURRENT_USER}${NC}"
echo -e "${GREEN}✓ Server: ${CURRENT_SERVER}${NC}"
echo ""

# Check current project
CURRENT_PROJECT=$(oc project -q 2>/dev/null || echo "")
if [ -z "$CURRENT_PROJECT" ]; then
    echo -e "${YELLOW}No project selected${NC}"
    read -p "Enter project name to create/use [news-service]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-news-service}

    if oc project "$PROJECT_NAME" &> /dev/null; then
        echo -e "${GREEN}✓ Switched to existing project: ${PROJECT_NAME}${NC}"
    else
        echo -e "${CYAN}Creating new project: ${PROJECT_NAME}${NC}"
        oc new-project "$PROJECT_NAME"
        echo -e "${GREEN}✓ Created and switched to project: ${PROJECT_NAME}${NC}"
    fi
else
    echo -e "${CYAN}Current project: ${CURRENT_PROJECT}${NC}"
    read -p "Deploy to this project? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        read -p "Enter project name to create/use: " PROJECT_NAME
        if oc project "$PROJECT_NAME" &> /dev/null; then
            echo -e "${GREEN}✓ Switched to existing project: ${PROJECT_NAME}${NC}"
        else
            echo -e "${CYAN}Creating new project: ${PROJECT_NAME}${NC}"
            oc new-project "$PROJECT_NAME"
            echo -e "${GREEN}✓ Created and switched to project: ${PROJECT_NAME}${NC}"
        fi
    fi
fi
echo ""

# Generate or load API key
echo -e "${CYAN}Configuring API key...${NC}"
if [ -f "$API_KEY_FILE" ]; then
    API_KEY=$(cat "$API_KEY_FILE")
    echo -e "${GREEN}✓ Using existing API key from ${API_KEY_FILE}${NC}"
else
    if command -v python3 &> /dev/null; then
        API_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    elif command -v python &> /dev/null; then
        API_KEY=$(python -c "import secrets; print(secrets.token_urlsafe(32))")
    else
        # Fallback to openssl
        API_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-43)
    fi
    echo "$API_KEY" > "$API_KEY_FILE"
    echo -e "${GREEN}✓ Generated new API key and saved to ${API_KEY_FILE}${NC}"
fi
echo ""

# Deploy PostgreSQL
echo -e "${CYAN}Step 1/7: Deploying PostgreSQL...${NC}"
oc apply -f openshift/postgres-deployment.yaml
echo -e "${GREEN}✓ PostgreSQL deployment created${NC}"
echo ""

# Wait for PostgreSQL to be ready
echo -e "${CYAN}Waiting for PostgreSQL to be ready...${NC}"
oc wait --for=condition=available --timeout=120s deployment/postgres || {
    echo -e "${YELLOW}⚠ PostgreSQL deployment timeout, checking status...${NC}"
    oc get pods -l app=news-service-db
}
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Initialize database
echo -e "${CYAN}Step 2/7: Initializing database schema...${NC}"
# Delete old job if exists
oc delete job news-service-init-db --ignore-not-found=true
oc apply -f openshift/init-db-job.yaml
echo "Waiting for database initialization..."
oc wait --for=condition=complete --timeout=60s job/news-service-init-db || {
    echo -e "${YELLOW}⚠ Checking job logs...${NC}"
    oc logs job/news-service-init-db
}
echo -e "${GREEN}✓ Database initialized${NC}"
echo ""

# Create ConfigMap
echo -e "${CYAN}Step 3/7: Creating ConfigMap...${NC}"
oc apply -f openshift/configmap.yaml
echo -e "${GREEN}✓ ConfigMap created${NC}"
echo ""

# Update API key in secret
echo -e "${CYAN}Step 4/7: Updating API key in secret...${NC}"
oc patch secret news-service-secrets -p "{\"stringData\":{\"API_KEY\":\"$API_KEY\"}}" --type=merge
echo -e "${GREEN}✓ API key configured${NC}"
echo ""

# Deploy news service
echo -e "${CYAN}Step 5/7: Deploying news service application...${NC}"
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml
echo -e "${GREEN}✓ News service deployed${NC}"
echo ""

# Wait for deployment
echo -e "${CYAN}Waiting for news service to be ready...${NC}"
oc wait --for=condition=available --timeout=120s deployment/news-service || {
    echo -e "${YELLOW}⚠ Deployment timeout, checking status...${NC}"
    oc get pods -l app=news-service
}
echo -e "${GREEN}✓ News service is ready${NC}"
echo ""

# Setup backups
echo -e "${CYAN}Step 6/7: Setting up automated backups...${NC}"
oc apply -f openshift/backup-cronjob.yaml
echo -e "${GREEN}✓ Backup CronJob created (runs daily at 2 AM)${NC}"
echo ""

# Get route URL
echo -e "${CYAN}Step 7/7: Getting service URL...${NC}"
ROUTE_URL=$(oc get route news-service -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE_URL" ]; then
    SERVICE_URL="https://$ROUTE_URL"
    echo -e "${GREEN}✓ Route created${NC}"
else
    echo -e "${YELLOW}⚠ Could not get route URL${NC}"
    SERVICE_URL="<checking...>"
fi
echo ""

# Summary
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${CYAN}Service Information:${NC}"
echo "  URL: $SERVICE_URL"
echo "  API Key: $API_KEY"
echo "  API Key File: $API_KEY_FILE"
echo ""
echo -e "${CYAN}Database Information:${NC}"
echo "  Host: postgres (internal service)"
echo "  Database: news"
echo "  Username: krisv"
echo "  Password: krisv"
echo ""
echo -e "${CYAN}Useful Commands:${NC}"
echo "  # View pods"
echo "  oc get pods"
echo ""
echo "  # View logs"
echo "  oc logs -f deployment/news-service"
echo ""
echo "  # Scale application"
echo "  oc scale deployment/news-service --replicas=3"
echo ""
echo "  # Manual backup"
echo "  oc create job --from=cronjob/postgres-backup manual-backup-\$(date +%s)"
echo ""
echo "  # Test API (without auth)"
echo "  curl $SERVICE_URL/health"
echo ""
echo "  # Test API (with auth)"
echo "  curl -X POST $SERVICE_URL/api/news \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-API-Key: $API_KEY' \\"
echo "    -d '{\"title\":\"Test\",\"content\":\"Hello\",\"labels\":[\"topic:AI\"]}'"
echo ""
echo -e "${GREEN}Deployment successful!${NC}"
