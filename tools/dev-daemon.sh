#!/bin/sh
# Run the daemon from this source tree in place of the installed one, under systemd
# (journal, watchdog). Stop it with: tools/dev-daemon.sh stop (the installed one comes back).
set -e
cd "$(dirname "$0")/.."
UNIT=boomerangd-dev
systemctl --user stop "$UNIT" 2>/dev/null || true
systemctl --user reset-failed "$UNIT" 2>/dev/null || true
if [ "$1" = stop ]; then
    systemctl --user start boomerangd
    exit 0
fi
systemctl --user stop boomerangd
systemd-run --user --unit="$UNIT" --collect -p WatchdogSec=30 -p NotifyAccess=main \
    -p Restart=on-failure --working-directory="$PWD" -E PYTHONPATH="$PWD" \
    python3 -c "import sys; from boomerangd.daemon import main; sys.exit(main())"
