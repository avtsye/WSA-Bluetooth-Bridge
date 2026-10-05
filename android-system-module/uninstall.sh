#!/system/bin/sh
pkill -f '/wsa-btd' 2>/dev/null || true
rm -f /data/local/tmp/wsa-bt-bridge.log
rm -f /data/local/tmp/wsa-bt-audio-env.txt
rm -f /data/local/tmp/wsa-bt-system-status.json
rm -f /data/local/tmp/wsa-bt-policy-state.json
rm -f /data/local/tmp/wsa-bt-health.json
rm -f /data/local/tmp/wsa-bt-enable-policy
rm -rf /data/local/tmp/wsa-bt-policy
