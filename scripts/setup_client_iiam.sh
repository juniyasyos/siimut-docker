#!/bin/bash

set -e

echo "🚀 Setting up CLIENT-IIAM project..."
echo ""
echo "Attempting to clone from GitHub repository: juniyasyos/client-iiam"
echo ""

# Try to use the clone script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/clone_client_iiam.sh" ]]; then
  exec "$SCRIPT_DIR/clone_client_iiam.sh" "$@"
else
  echo "Error: clone_client_iiam.sh not found" >&2
  echo "Please run: ./scripts/clone_client_iiam.sh" >&2
  exit 1
fi
