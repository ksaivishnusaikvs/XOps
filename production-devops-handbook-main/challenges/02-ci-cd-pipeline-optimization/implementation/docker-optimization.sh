#!/bin/bash
#
# Docker Build Optimization Script
# Implements multi-stage builds, layer caching, and BuildKit features
#
# Usage: ./docker-optimization.sh [options]
#

set -euo pipefail

# Configuration
IMAGE_NAME="${IMAGE_NAME:-myapp}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"
USE_BUILDKIT="${USE_BUILDKIT:-1}"
CACHE_FROM="${CACHE_FROM:-}"
CACHE_TO="${CACHE_TO:-}"
PLATFORM="${PLATFORM:-linux/amd64}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

log "Starting optimized Docker build..."
log "Image: $IMAGE_NAME:$IMAGE_TAG"

# Enable BuildKit for faster builds
export DOCKER_BUILDKIT=$USE_BUILDKIT

# Build arguments
BUILD_ARGS=(
    "--tag" "$IMAGE_NAME:$IMAGE_TAG"
    "--build-arg" "BUILDKIT_INLINE_CACHE=1"
    "--platform" "$PLATFORM"
)

# Add cache configuration
if [ -n "$CACHE_FROM" ]; then
    BUILD_ARGS+=("--cache-from" "$CACHE_FROM")
fi

if [ -n "$CACHE_TO" ]; then
    BUILD_ARGS+=("--cache-to" "$CACHE_TO")
fi

# Add registry prefix if specified
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    BUILD_ARGS+=("--tag" "$FULL_IMAGE")
fi

# Build with optimizations
log "Building with BuildKit optimizations..."
docker build "${BUILD_ARGS[@]}" .

# Analyze image size
log "Analyzing image size..."
docker images "$IMAGE_NAME:$IMAGE_TAG" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Scan for vulnerabilities (if trivy is available)
if command -v trivy &> /dev/null; then
    log "Scanning for vulnerabilities..."
    trivy image --severity HIGH,CRITICAL "$IMAGE_NAME:$IMAGE_TAG"
fi

# Push to registry if specified
if [ -n "$REGISTRY" ]; then
    log "Pushing to registry: $REGISTRY"
    docker push "$FULL_IMAGE"
fi

log "Build complete!"
