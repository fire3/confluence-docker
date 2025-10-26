#!/usr/bin/env bash
set -euo pipefail

# Configure environment directories and default .env for compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [default|lts|/path/to/compose.yml]

Creates necessary directories, sets permissions, and generates an optional .env file.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; print_usage_common; exit 0
fi

compose_file="$(resolve_compose_file "${1:-}")"

# Create data directories for volumes
# From compose: home_data -> /var/confluence, mysql_data -> /var/lib/mysql
mkdir -p /var/confluence /var/lib/mysql

# Recommended permissions (may be adjusted later)
# Confluence runs in container; host permissions are not strictly required, but ensure writable
chmod 0777 /var/confluence || true
chmod 0777 /var/lib/mysql || true

# Generate .env to override JVM memory (optional)
ENV_FILE="$REPO_DIR/.env"
cat > "$ENV_FILE" <<EOF
# Optional overrides for compose
TZ=Asia/Shanghai
# JVM_MINIMUM_MEMORY=4g
# JVM_MAXIMUM_MEMORY=16g
EOF

echo "Environment configured. Data dirs ready and .env at $ENV_FILE"
