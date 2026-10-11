#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
# Covalence was renamed Boomerang in 0.7.0. Covalence 0.6 updates itself only to a
# package named « covalence » (its install helper refuses any other name), so each
# release also carries covalence_<version>_<arch>.deb: the same files as Boomerang
# under the old package name. The next Boomerang update then replaces it with the
# « boomerang » package (Conflicts/Replaces), and nothing named covalence is left.
#
# Usage: packaging/transitional-deb.sh dist/boomerang_<version>_<arch>.deb
set -eu
src=$1
out=$(echo "$src" | sed 's#boomerang_#covalence_#')
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dpkg-deb -R "$src" "$work/root"
control="$work/root/DEBIAN/control"
sed -i -e 's/^Package: boomerang$/Package: covalence/' \
       -e '/^Provides:/d' -e '/^Conflicts:/d' -e '/^Replaces:/d' "$control"
sed -i '/^Package:/a Provides: boomerang\nConflicts: boomerang\nReplaces: boomerang' "$control"
sed -i 's/^Description: .*/Description: Boomerang, anciennement Covalence (paquet de transition)/' "$control"
dpkg-deb --root-owner-group -Zxz --build "$work/root" "$out" >/dev/null
echo "$out"
