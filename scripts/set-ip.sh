#!/usr/bin/env bash
# Updates the hard-coded API/WebSocket host across iOS code + ATS Info.plist exception.
# Usage:
#   ./scripts/set-ip.sh                # auto-detects current Mac Wi-Fi IP (en0)
#   ./scripts/set-ip.sh 172.20.10.2    # forces a specific IP

set -euo pipefail

NEW_IP="${1:-$(ipconfig getifaddr en0 2>/dev/null || echo "")}"
if [ -z "$NEW_IP" ]; then
  echo "No IP detected on en0 and none provided." >&2
  echo "Usage: $0 [IP]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK="$ROOT/NFTArts/Services/NetworkService.swift"
WEBSOCK="$ROOT/NFTArts/Services/WebSocketService.swift"
PLIST="$ROOT/NFTArts/Info.plist"

OLD_IP_NETWORK=$(grep -oE "http://[0-9.]+:8080" "$NETWORK" | head -1 | sed -E 's|http://([0-9.]+):8080|\1|')
OLD_IP_WS=$(grep -oE "ws://[0-9.]+:8080" "$WEBSOCK" | head -1 | sed -E 's|ws://([0-9.]+):8080|\1|')

echo "New host:        $NEW_IP"
echo "Current NetworkService: $OLD_IP_NETWORK"
echo "Current WebSocket:      $OLD_IP_WS"
echo

# 1. NetworkService
sed -i.bak -E "s|http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080|http://$NEW_IP:8080|" "$NETWORK"

# 2. WebSocketService
sed -i.bak -E "s|ws://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080|ws://$NEW_IP:8080|" "$WEBSOCK"

# 3. Info.plist — replace old IP key with new IP if present, else add new exception block.
if grep -q "<key>$NEW_IP</key>" "$PLIST"; then
  echo "Info.plist already contains $NEW_IP (no change needed)"
else
  # Replace first non-localhost IPv4 key inside NSExceptionDomains
  python3 - "$PLIST" "$NEW_IP" <<'PY'
import sys, re
plist_path, new_ip = sys.argv[1], sys.argv[2]
src = open(plist_path).read()
# Look for any existing IPv4 key inside NSExceptionDomains and replace its key value
m = re.search(r'(<key>NSExceptionDomains</key>\s*<dict>.*?)<key>(\d+\.\d+\.\d+\.\d+)</key>', src, re.DOTALL)
if m:
    old = m.group(2)
    if old != new_ip:
        # Insert a new exception entry next to the existing one (do not remove old).
        insert = f'\n\t\t\t<key>{new_ip}</key>\n\t\t\t<dict>\n\t\t\t\t<key>NSExceptionAllowsInsecureHTTPLoads</key>\n\t\t\t\t<true/>\n\t\t\t</dict>'
        idx = src.find('<key>NSExceptionDomains</key>')
        # Insert after the opening <dict> that follows.
        dict_start = src.find('<dict>', idx) + len('<dict>')
        src = src[:dict_start] + insert + src[dict_start:]
        open(plist_path, 'w').write(src)
        print(f"Info.plist: added exception for {new_ip}")
    else:
        print("Info.plist already correct")
else:
    print("WARNING: NSExceptionDomains block not found in Info.plist", file=sys.stderr)
PY
fi

# Clean .bak files
rm -f "$NETWORK.bak" "$WEBSOCK.bak"

echo
echo "Done. New endpoints:"
echo "  REST: http://$NEW_IP:8080/api/v1"
echo "  WS:   ws://$NEW_IP:8080"
echo
echo "Next: in Xcode press Cmd+Shift+K (Clean Build Folder), then Cmd+R."
