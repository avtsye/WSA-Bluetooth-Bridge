#!/system/bin/sh
pkill -f '/wsa-btd' 2>/dev/null || true
rm -f /data/local/tmp/wsa-bt-bridge.log
