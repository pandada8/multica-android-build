#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:?Usage: apply-patches.sh /path/to/upstream}
# Check and apply sequentially: later patches may depend on earlier ones.
for patch in "$root"/patches/*.patch; do
  git -C "$source_dir" apply --check "$patch"
  git -C "$source_dir" apply "$patch"
done
