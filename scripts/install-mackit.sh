#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_source="$repo_root/.build/MacKit.app"
app_destination="$HOME/Applications/MacKit.app"
cli_destination="$HOME/.local/bin/mackit"

"$repo_root/scripts/build-mackit-app.sh" >/dev/null
bin_dir="$(swift build -c release --show-bin-path)"

pkill -x MacKitHost 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$app_destination"
ditto "$app_source" "$app_destination"
cp "$bin_dir/mackit" "$cli_destination"
chmod +x "$cli_destination"

echo "Installed MacKit.app to $app_destination"
echo "Installed mackit to $cli_destination"
