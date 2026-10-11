#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
# Build boomerang_<version>_<arch>.deb in dist/.
#
# Normal path: dpkg-buildpackage (needs the Build-Depends of debian/control,
# debhelper included). When they are not all installed, or with --quick, the
# same tree is built with meson + DESTDIR and packed with dpkg-deb: the result
# has the same files, control fields and maintainer scripts, without the dh_*
# checks.
set -eu

top=$(cd "$(dirname "$0")/.." && pwd)
cd "$top"
mkdir -p dist

version=$(dpkg-parsechangelog -S Version)
arch=$(dpkg-architecture -qDEB_HOST_ARCH)

if [ "${1:-}" != "--quick" ] && dpkg-checkbuilddeps 2>/dev/null; then
    dpkg-buildpackage -us -uc -b
    mv ../boomerang_"$version"_"$arch".deb dist/
    rm -f ../boomerang_"$version"_"$arch".buildinfo ../boomerang_"$version"_"$arch".changes \
          ../boomerang-dbgsym_"$version"_"$arch".ddeb
    echo "dist/boomerang_${version}_${arch}.deb"
    sh packaging/transitional-deb.sh "dist/boomerang_${version}_${arch}.deb"
    exit 0
fi

if [ "${1:-}" != "--quick" ]; then
    echo "Missing build dependencies, falling back to meson + dpkg-deb:" >&2
    dpkg-checkbuilddeps 2>&1 | sed 's/^/  /' >&2 || true
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/root"

meson setup "$work/build" --prefix=/usr --buildtype=release >/dev/null
meson compile -C "$work/build" >/dev/null
DESTDIR="$root" meson install -C "$work/build" --no-rebuild >/dev/null
# Post-install hooks (icon cache, desktop database) belong to the target system.
rm -f "$root/usr/share/icons/hicolor/icon-theme.cache" \
      "$root/usr/share/applications/mimeinfo.cache"
find "$root" -name __pycache__ -type d -prune -exec rm -rf {} +
strip --strip-unneeded "$root/usr/bin/io.github.melvincouwez.Boomerang"

install -Dm644 debian/copyright "$root/usr/share/doc/boomerang/copyright"
gzip -9n -c debian/changelog > "$work/changelog.Debian.gz"
install -Dm644 "$work/changelog.Debian.gz" "$root/usr/share/doc/boomerang/changelog.Debian.gz"

mkdir -p "$root/DEBIAN"
for script in postinst prerm postrm; do
    sed '/#DEBHELPER#/d' "debian/$script" > "$root/DEBIAN/$script"
    chmod 755 "$root/DEBIAN/$script"
done

# ${shlibs:Depends} from the binary, then control from debian/control.
cp -r debian "$work/pkg-debian"
( cd "$work" && ln -s pkg-debian debian &&
  dpkg-shlibdeps -O "-e$root/usr/bin/io.github.melvincouwez.Boomerang" 2>/dev/null ) > "$work/substvars"
# dpkg-shlibdeps takes the version from the build machine's symbols file, where elementary's
# daily PPA dates granite_header_label_set_secondary_text 7.8.0 (the property exists since 7.1).
# The newest API Boomerang really uses is HeaderLabel.size (Granite 7.7.0).
sed -i 's/libgranite7 ([^)]*)/libgranite7 (>= 7.7.0)/' "$work/substvars"
# elementary's own packages name Granite libgranite7, Ubuntu's libgranite-7-7: accept both.
sed -i 's/libgranite7 (\([^)]*\))/libgranite7 (\1) | libgranite-7-7 (\1)/' "$work/substvars"
echo "misc:Depends=" >> "$work/substvars"
size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
dpkg-gencontrol -pboomerang -c"debian/control" -l"debian/changelog" -T"$work/substvars" \
    -P"$root" -O"$root/DEBIAN/control" -DInstalled-Size="$size"
sed -i '/^Installed-Size:/d' "$root/DEBIAN/control"
echo "Installed-Size: $size" >> "$root/DEBIAN/control"

dpkg-deb --root-owner-group -Zxz --build "$root" "dist/boomerang_${version}_${arch}.deb" >/dev/null
echo "dist/boomerang_${version}_${arch}.deb"
sh packaging/transitional-deb.sh "dist/boomerang_${version}_${arch}.deb"
