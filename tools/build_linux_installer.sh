#!/usr/bin/env bash
# Build a Linux release bundle and an installable Debian package.
#
# Run this on Linux, not Windows:
#   tools/build_linux_installer.sh
#   tools/build_linux_installer.sh --skip-flutter-build
#   tools/build_linux_installer.sh --no-tar
#   tools/build_linux_installer.sh --no-deb
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec="$repo_root/pubspec.yaml"
bundle_dir="$repo_root/build/linux/x64/release/bundle"
cores_dir="$repo_root/tools/cores/linux"

package_name="temnyivpn"
app_binary="entropy_vpn"
app_display_name="TemnyiVPN"
install_dir="/opt/entropy_vpn"
skip_flutter_build=0
make_tarball=1
make_deb=1

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}"
}

for arg in "$@"; do
  case "$arg" in
    --skip-flutter-build) skip_flutter_build=1 ;;
    --no-tar) make_tarball=0 ;;
    --no-deb) make_deb=0 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

require_file() {
  if [ ! -f "$1" ]; then
    echo "Required file not found: $1" >&2
    exit 1
  fi
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

require_file "$pubspec"

app_version="$(grep -E '^version:' "$pubspec" | head -n1 | awk '{print $2}' | cut -d+ -f1)"
if [ -z "$app_version" ]; then
  echo "Could not parse version from $pubspec" >&2
  exit 1
fi

if [ ! -d "$cores_dir" ] || [ -z "$(ls -A "$cores_dir" 2>/dev/null || true)" ]; then
  echo "WARNING: $cores_dir is empty. The Linux package will have no core binaries." >&2
  echo "         Drop xray and sing-box Linux binaries there and chmod +x them." >&2
fi

if [ "$skip_flutter_build" -ne 1 ]; then
  require_tool flutter
  (cd "$repo_root" && flutter build linux --release)
fi

if [ ! -x "$bundle_dir/$app_binary" ]; then
  echo "Linux release bundle not found at $bundle_dir" >&2
  echo "Run this script on Linux with Flutter Linux desktop support enabled." >&2
  exit 1
fi

dist_dir="$repo_root/build/linux/dist"
mkdir -p "$dist_dir"

if [ "$make_tarball" -eq 1 ]; then
  tarball="$dist_dir/entropy_vpn-${app_version}-linux-x64.tar.gz"
  tmp_stage="$(mktemp -d)"
  trap 'rm -rf "$tmp_stage"' EXIT
  cp -a "$bundle_dir" "$tmp_stage/entropy_vpn"
  tar -C "$tmp_stage" -czf "$tarball" entropy_vpn
  echo "Tarball: $tarball"
fi

if [ "$make_deb" -eq 1 ]; then
  require_tool dpkg-deb

  deb_arch="$(dpkg --print-architecture 2>/dev/null || true)"
  if [ -z "$deb_arch" ]; then
    case "$(uname -m)" in
      x86_64) deb_arch="amd64" ;;
      aarch64|arm64) deb_arch="arm64" ;;
      armv7l|armhf) deb_arch="armhf" ;;
      *) deb_arch="$(uname -m)" ;;
    esac
  fi

  deb_root="$(mktemp -d)"
  trap 'rm -rf "${tmp_stage:-}" "$deb_root"' EXIT

  mkdir -p \
    "$deb_root/DEBIAN" \
    "$deb_root$install_dir" \
    "$deb_root/usr/bin" \
    "$deb_root/usr/share/applications" \
    "$deb_root/usr/share/icons/hicolor/512x512/apps"

  cp -a "$bundle_dir/." "$deb_root$install_dir/"

  if [ -f "$deb_root$install_dir/share/applications/entropy_vpn.desktop" ]; then
    cp "$deb_root$install_dir/share/applications/entropy_vpn.desktop" \
      "$deb_root/usr/share/applications/entropy_vpn.desktop"
  elif [ -f "$repo_root/linux/entropy_vpn.desktop" ]; then
    cp "$repo_root/linux/entropy_vpn.desktop" \
      "$deb_root/usr/share/applications/entropy_vpn.desktop"
  fi

  if [ -f "$deb_root$install_dir/share/icons/hicolor/512x512/apps/entropy_vpn.png" ]; then
    cp "$deb_root$install_dir/share/icons/hicolor/512x512/apps/entropy_vpn.png" \
      "$deb_root/usr/share/icons/hicolor/512x512/apps/entropy_vpn.png"
  elif [ -f "$repo_root/entropylogo.png" ]; then
    cp "$repo_root/entropylogo.png" \
      "$deb_root/usr/share/icons/hicolor/512x512/apps/entropy_vpn.png"
  fi

  ln -s "$install_dir/$app_binary" "$deb_root/usr/bin/$app_binary"

  find "$deb_root$install_dir" -type d -exec chmod 755 {} +
  chmod 755 "$deb_root$install_dir/$app_binary"
  if [ -d "$deb_root$install_dir/cores" ]; then
    find "$deb_root$install_dir/cores" -type f -exec chmod 755 {} +
  fi
  if [ -f "$deb_root$install_dir/share/entropy_vpn/helpers/entropy_vpn_runner.sh" ]; then
    chmod 755 "$deb_root$install_dir/share/entropy_vpn/helpers/entropy_vpn_runner.sh"
  fi

  installed_size="$(du -sk "$deb_root" | awk '{print $1}')"
  cat >"$deb_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $app_version
Section: net
Priority: optional
Architecture: $deb_arch
Installed-Size: $installed_size
Maintainer: TemnyiVPN <support@temnyivpn.local>
Depends: libgtk-3-0 | libgtk-3-0t64, libstdc++6, libc6, policykit-1 | polkitd
Description: $app_display_name VPN client
 Xray-core and sing-box VPN client with Linux desktop integration.
EOF

  cat >"$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
exit 0
EOF
  chmod 755 "$deb_root/DEBIAN/postinst"

  deb_path="$dist_dir/${package_name}_${app_version}_${deb_arch}.deb"
  dpkg-deb --build --root-owner-group "$deb_root" "$deb_path"
  echo "Debian package: $deb_path"
  echo "Install with: sudo apt install ./$deb_path"
fi
