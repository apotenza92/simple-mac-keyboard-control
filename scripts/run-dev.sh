#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="${repo_dir}/build/Simple Mac Keyboard Control Dev.app"
install_dir="${HOME}/Applications"
installed_app="${install_dir}/KeyControl Dev.app"

"${repo_dir}/scripts/build-app.sh"
pkill -f "^${installed_app}/Contents/MacOS/KeyControl$" 2>/dev/null || true
mkdir -p "${install_dir}"
rm -rf "${installed_app:?}"
/usr/bin/ditto "${source_app}" "${installed_app}"
open -na "${installed_app}" --args "$@"

sleep 2
echo "Running stable development app: ${installed_app}"
