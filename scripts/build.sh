#!/bin/sh
# Build the chatmail Docker image with the current git hash baked in.
# Usage: ./docker/build.sh [extra docker-compose build args...]
#
# .git/ is excluded from the build context (.dockerignore) so the hash
# must be passed as a build arg from the host.

export GIT_HASH=$(git rev-parse HEAD)
export SOURCE_REF=$(git symbolic-ref --short HEAD 2>/dev/null || echo "$GIT_HASH")
export SOURCE_URL=$(git remote get-url origin 2>/dev/null || echo "unknown")
export BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cp "$(dirname "$0")/../.dockerignore" .dockerignore
exec docker compose -f docker/docker-compose.yaml build "$@"
