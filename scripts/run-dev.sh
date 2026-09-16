#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="${repo_dir}/build/Simple Mac Keyboard Control Dev.app"
install_dir="${HOME}/Applications"
installed_app="${install_dir}/KeyControl Dev.app"

"${repo_dir}/scripts/build-app.sh"
# A blanket pkill would also kill the process restoring disabled displays.
python3 - "${installed_app}/Contents/MacOS/KeyControl" <<'PY'
import subprocess, sys, time
executable = sys.argv[1]
def running():
    commands = subprocess.check_output(['ps', '-axo', 'command='], text=True).splitlines()
    return [c for c in commands if c == executable or c.startswith(executable + ' ')]
commands = running()
if any('--display-prototype' in c for c in commands):
    raise SystemExit('Finish the bounded display prototype before reinstalling the development app.')
if any('--display-recovery' not in c for c in commands):
    subprocess.run(['osascript', '-e', 'tell application id "com.apotenza.KeyControl.dev" to quit'], check=True, timeout=15)
deadline = time.monotonic() + 12
while running() and time.monotonic() < deadline:
    time.sleep(.1)
if running():
    raise SystemExit('Development app or display recovery is still running; installation was not changed.')
PY
mkdir -p "${install_dir}"
rm -rf "${installed_app:?}"
/usr/bin/ditto "${source_app}" "${installed_app}"
open -na "${installed_app}" --args "$@"

sleep 2
echo "Running stable development app: ${installed_app}"
