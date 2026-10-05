#!/system/bin/sh
rm -f /data/local/tmp/wsa-bt-enable-policy
rm -f /data/adb/modules/wsa_bt_bridge/disable 2>/dev/null || true
echo '{"activation_requested":false,"restart_required":true}' > /data/local/tmp/wsa-bt-policy-state.json
echo "WSA Bluetooth audio policy disabled. Restart Android/WSA to return to diagnostic-only mode."
