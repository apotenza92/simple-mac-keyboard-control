#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/xcode-env.sh"
python3 "$repo_dir/scripts/generate-icon-assets.py"
for icon in AppIcon AppIconBeta; do
    destination="$repo_dir/Resources/CompiledIcons/$icon"
    mkdir -p "$destination"
    xcrun actool "$repo_dir/Resources/$icon.icon" --compile "$destination" \
        --output-format human-readable-text --output-partial-info-plist "$destination/info.plist" \
        --app-icon "$icon" --include-all-app-icons --enable-on-demand-resources NO \
        --development-region en --target-device mac --minimum-deployment-target 14.4 --platform macosx
done
python3 "$repo_dir/scripts/verify-compiled-icons.py" --record
