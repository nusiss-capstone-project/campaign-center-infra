#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> terraform fmt (recursive)"
terraform -chdir="${ROOT_DIR}" fmt -recursive
