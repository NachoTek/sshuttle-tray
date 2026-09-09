#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if kpackagetool6 -t "Plasma/Applet" -u . 2>/dev/null; then
    echo "Updated org.nachotek.sshuttletray.proto"
else
    kpackagetool6 -t "Plasma/Applet" -i .
    echo "Installed org.nachotek.sshuttletray.proto"
fi
