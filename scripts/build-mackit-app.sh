#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
resources="$repo_root/Resources/MacKitHost"
app_dir="${MACKIT_APP_OUTPUT:-$repo_root/.build/MacKit.app}"
contents="$app_dir/Contents"
macos_dir="$contents/MacOS"
helpers_dir="$contents/Helpers"
identity="${MACKIT_CODESIGN_IDENTITY:--}"

swift build -c release --product mackit
swift build -c release --product MacKitHost
bin_dir="$(swift build -c release --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$helpers_dir"
cp "$resources/Info.plist" "$contents/Info.plist"
cp "$bin_dir/MacKitHost" "$macos_dir/MacKitHost"
cp "$bin_dir/mackit" "$helpers_dir/mackit"

codesign --force --sign "$identity" --options runtime "$helpers_dir/mackit"

signing_arguments=(
  --force
  --sign "$identity"
  --options runtime
  --entitlements "$resources/MacKitHost.entitlements"
)
if [[ "$identity" == "-" ]]; then
  signing_arguments+=(--requirements '=designated => identifier "dev.mackit.host"')
fi
codesign "${signing_arguments[@]}" "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
