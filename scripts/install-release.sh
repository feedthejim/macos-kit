#!/bin/zsh
set -euo pipefail

release_dir="${0:A:h}"
app_destination="$HOME/Applications/MacKit.app"
cli_destination="$HOME/.local/bin/mackit"

guard_file="$release_dir/MacKit.app/Contents/MacOS/MacKitHost"
if [[ ! -x "$guard_file" || ! -x "$release_dir/mackit" ]]; then
  print -u2 "The release archive is missing MacKit.app or mackit."
  exit 66
fi

pkill -x MacKitHost 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$app_destination"
ditto "$release_dir/MacKit.app" "$app_destination"
cp "$release_dir/mackit" "$cli_destination"
chmod +x "$cli_destination"

echo "Installed MacKit.app to $app_destination"
echo "Installed mackit to $cli_destination"
