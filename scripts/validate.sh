#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ROOT_DIR}/terraform/environments/dev"

echo "==> terraform fmt (recursive)"
terraform -chdir="${ROOT_DIR}" fmt -recursive -check

echo "==> terraform init (dev)"
terraform -chdir="${ENV_DIR}" init -backend=false

echo "==> terraform validate (dev)"
terraform -chdir="${ENV_DIR}" validate
