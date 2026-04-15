#!/bin/bash
# Build and push Docker image to Quay.io

set -e

echo "=========================================="
echo "News Service - Build & Push to Quay.io"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration file for Quay username
CONFIG_FILE=".quay-config"

# Check if docker or podman is available
CONTAINER_CLI=""
if command -v docker &> /dev/null; then
    CONTAINER_CLI="docker"
    echo -e "${GREEN}✓ Using Docker${NC}"
elif command -v podman &> /dev/null; then
    CONTAINER_CLI="podman"
    echo -e "${GREEN}✓ Using Podman${NC}"
else
    echo -e "${RED}✗ Error: Neither Docker nor Podman found${NC}"
    echo "Please install Docker or Podman"
    exit 1
fi
echo ""

# Get Quay.io username
echo -e "${CYAN}Quay.io Configuration${NC}"
if [ -f "$CONFIG_FILE" ]; then
    QUAY_USERNAME=$(cat "$CONFIG_FILE")
    echo -e "Current username: ${GREEN}${QUAY_USERNAME}${NC}"
    read -p "Use this username? [Y/n]: " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-Y}
    if [[ ! $USE_EXISTING =~ ^[Yy]$ ]]; then
        read -p "Enter Quay.io username: " QUAY_USERNAME
        echo "$QUAY_USERNAME" > "$CONFIG_FILE"
        echo -e "${GREEN}✓ Username saved to ${CONFIG_FILE}${NC}"
    fi
else
    read -p "Enter Quay.io username: " QUAY_USERNAME
    if [ -z "$QUAY_USERNAME" ]; then
        echo -e "${RED}✗ Error: Username cannot be empty${NC}"
        exit 1
    fi
    echo "$QUAY_USERNAME" > "$CONFIG_FILE"
    echo -e "${GREEN}✓ Username saved to ${CONFIG_FILE}${NC}"
fi
echo ""

# Get version tag
echo -e "${CYAN}Image Version${NC}"
read -p "Enter version tag [latest]: " VERSION
VERSION=${VERSION:-latest}
echo ""

# Image names
IMAGE_NAME="news-service"
FULL_IMAGE="quay.io/${QUAY_USERNAME}/${IMAGE_NAME}:${VERSION}"

# Build image
echo -e "${CYAN}Step 1/4: Building Docker image...${NC}"
echo "Image: ${FULL_IMAGE}"
$CONTAINER_CLI build -t "${IMAGE_NAME}:${VERSION}" -t "${IMAGE_NAME}:latest" .
echo -e "${GREEN}✓ Image built successfully${NC}"
echo ""

# Tag for Quay.io
echo -e "${CYAN}Step 2/4: Tagging image for Quay.io...${NC}"
$CONTAINER_CLI tag "${IMAGE_NAME}:${VERSION}" "${FULL_IMAGE}"
if [ "$VERSION" != "latest" ]; then
    $CONTAINER_CLI tag "${IMAGE_NAME}:${VERSION}" "quay.io/${QUAY_USERNAME}/${IMAGE_NAME}:latest"
fi
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

# Check if logged in to Quay.io
echo -e "${CYAN}Step 3/4: Checking Quay.io login...${NC}"
if ! $CONTAINER_CLI login quay.io --get-login &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Quay.io${NC}"
    echo "Attempting to login..."
    $CONTAINER_CLI login quay.io
else
    LOGGED_IN_USER=$($CONTAINER_CLI login quay.io --get-login)
    echo -e "${GREEN}✓ Already logged in as: ${LOGGED_IN_USER}${NC}"
fi
echo ""

# Push image
echo -e "${CYAN}Step 4/4: Pushing image to Quay.io...${NC}"
$CONTAINER_CLI push "${FULL_IMAGE}"
if [ "$VERSION" != "latest" ]; then
    echo "Also pushing as latest..."
    $CONTAINER_CLI push "quay.io/${QUAY_USERNAME}/${IMAGE_NAME}:latest"
fi
echo -e "${GREEN}✓ Image pushed successfully${NC}"
echo ""

# Ask to update deployment.yaml
echo -e "${CYAN}Update deployment configuration?${NC}"
DEPLOYMENT_FILE="openshift/deployment.yaml"
if [ -f "$DEPLOYMENT_FILE" ]; then
    CURRENT_IMAGE=$(grep -E "^\s+image:" "$DEPLOYMENT_FILE" | awk '{print $2}' | head -1)
    echo "Current image in deployment.yaml: ${CURRENT_IMAGE}"
    echo "New image: ${FULL_IMAGE}"
    read -p "Update deployment.yaml with new image? [Y/n]: " UPDATE_DEPLOYMENT
    UPDATE_DEPLOYMENT=${UPDATE_DEPLOYMENT:-Y}

    if [[ $UPDATE_DEPLOYMENT =~ ^[Yy]$ ]]; then
        # Backup original
        cp "$DEPLOYMENT_FILE" "${DEPLOYMENT_FILE}.bak"

        # Update image line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed
            sed -i '' "s|image:.*|image: ${FULL_IMAGE}|" "$DEPLOYMENT_FILE"
        else
            # Linux sed
            sed -i "s|image:.*|image: ${FULL_IMAGE}|" "$DEPLOYMENT_FILE"
        fi

        echo -e "${GREEN}✓ Updated ${DEPLOYMENT_FILE}${NC}"
        echo -e "${YELLOW}  Backup saved to ${DEPLOYMENT_FILE}.bak${NC}"
    fi
fi
echo ""

# Summary
echo "=========================================="
echo -e "${GREEN}Build & Push Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${CYAN}Image Information:${NC}"
echo "  Registry: quay.io"
echo "  Repository: ${QUAY_USERNAME}/${IMAGE_NAME}"
echo "  Tag: ${VERSION}"
echo "  Full: ${FULL_IMAGE}"
echo ""
echo -e "${CYAN}Image URLs:${NC}"
echo "  https://quay.io/repository/${QUAY_USERNAME}/${IMAGE_NAME}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
if [[ $UPDATE_DEPLOYMENT =~ ^[Yy]$ ]]; then
    echo "  1. Review changes in ${DEPLOYMENT_FILE}"
    echo "  2. Deploy to OpenShift:"
    echo "     ./deploy.sh"
else
    echo "  1. Update ${DEPLOYMENT_FILE} with the new image"
    echo "  2. Deploy to OpenShift:"
    echo "     ./deploy.sh"
fi
echo ""
echo "  Or update running deployment directly:"
echo "  oc set image deployment/news-service news-service=${FULL_IMAGE}"
echo ""
echo -e "${GREEN}Build successful!${NC}"
