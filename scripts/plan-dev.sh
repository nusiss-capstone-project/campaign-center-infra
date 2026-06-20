#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ROOT_DIR}/terraform/environments/dev"

terraform -chdir="${ENV_DIR}" init
terraform -chdir="${ENV_DIR}" plan "$@"
