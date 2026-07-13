#!/bin/bash
# Fix ACME agreement acceptance in running chatmail container
# Usage: ./fix-acme-agreement.sh [email] [container_name]

set -e

ACME_EMAIL="${1}"
CONTAINER_NAME="${2:-chatmail}"

# Try to load email from .env if not provided
if [ -z "$ACME_EMAIL" ] && [ -f .env ]; then
    ACME_EMAIL=$(grep -E "^ACME_EMAIL=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

if [ -z "$ACME_EMAIL" ]; then
    echo "Error: Email address required"
    echo "Usage: $0 <email> [container_name]"
    echo "   or: Set ACME_EMAIL in .env file"
    exit 1
fi

echo "==> Creating ACME responses file in container: $CONTAINER_NAME"
echo "    Email: $ACME_EMAIL"

docker exec "$CONTAINER_NAME" bash -c "cat > /var/lib/acme/conf/responses << \"EOF\"
\"acme-enter-email\": \"$ACME_EMAIL\"
\"acme-agreement:https://letsencrypt.org/documents/LE-SA-v1.7-June-04-2026.pdf\": true
\"acme-agreement:https://letsencrypt.org/documents/LE-SA-v1.8-July-06-2026.pdf\": true
EOF"

echo "==> ACME responses file created successfully"

echo "==> Running acmetool reconcile to obtain certificates..."

docker exec "$CONTAINER_NAME" acmetool reconcile --batch

echo "==> Done! Check certificate status with:"
echo "    docker exec $CONTAINER_NAME acmetool status"
