#!/bin/sh
# Screenshots of the app with the demo daemon, off screen (Broadway), never on the desktop.
#   tools/snapshots.sh [build dir] [out dir] [page...]
# Env: BOOMERANG_DEMO_LINK=absent|classic|... (link state), SNAP_THEME=dark, SNAP_SIZE=1080x740.
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-build-dev}; OUT=${2:-.impeccable/review}; shift 2 2>/dev/null || shift $#
PAGES=${*:-messages phone contacts notifications nowplaying device modules}
mkdir -p "$OUT"
TMP=$(mktemp -d)
mkdir -p "$TMP/config/boomerang" "$TMP/share/icons/hicolor/scalable/apps"
# The app's own icons from the tree: new ones are not installed yet.
cp data/icons/*.svg "$TMP/share/icons/hicolor/scalable/apps/"
VERSION=$(sed -n "s/^  version: '\(.*\)',$/\1/p" meson.build)
# Setup done and this version's « what's new » seen: the window itself, nothing on top.
printf '[setup]\ndone=true\n[general]\nwhats-new=%s\n' "$VERSION" > "$TMP/config/boomerang/apps.conf"
if [ "$SNAP_THEME" = dark ]; then
    mkdir -p "$TMP/config/gtk-4.0"
    printf '[Settings]\ngtk-application-prefer-dark-theme=true\ngtk-interface-color-scheme=dark\n' > "$TMP/config/gtk-4.0/settings.ini"
fi
DISPLAY_NUM=:$((7 + $$ % 50))
gtk4-broadwayd "$DISPLAY_NUM" >/dev/null 2>&1 &
BROADWAY=$!
BUS=io.github.melvincouwez.Boomerang.Demo$$
BOOMERANG_DEMO_BUS=$BUS python3 tools/demo_daemon.py >/dev/null 2>&1 &
DEMO=$!
trap 'kill $BROADWAY $DEMO 2>/dev/null; rm -rf "$TMP"' EXIT
sleep 1
for page in $PAGES; do
    suffix=${SNAP_SUFFIX:+-$SNAP_SUFFIX}
    GDK_BACKEND=broadway BROADWAY_DISPLAY=$DISPLAY_NUM XDG_CONFIG_HOME="$TMP/config" \
        BOOMERANG_DAEMON_NAME=$BUS BOOMERANG_SNAPSHOT="$PWD/$OUT/$page$suffix.png" \
        BOOMERANG_SNAPSHOT_SIZE=${SNAP_SIZE:-1080x740} GSETTINGS_BACKEND=memory \
        XDG_DATA_DIRS="$TMP/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        timeout 12 "${BIN:-$BUILD/src/io.github.melvincouwez.Boomerang}" --page "$page" >/dev/null 2>&1 || true
    [ -f "$OUT/$page$suffix.png" ] && echo "$OUT/$page$suffix.png"
done
