#!/system/bin/sh
OUT=/data/local/tmp/wsa-bt-audio-env.txt
STATUS=/data/local/tmp/wsa-bt-system-status.json

{
  echo "=== WSA Bluetooth Bridge audio environment ==="
  echo "timestamp=$(date -Iseconds 2>/dev/null || date)"
  echo "abi=$(getprop ro.product.cpu.abi)"
  echo "android_release=$(getprop ro.build.version.release)"
  echo "sdk=$(getprop ro.build.version.sdk)"
  echo "fingerprint=$(getprop ro.build.fingerprint)"
  echo "selinux=$(getenforce 2>/dev/null)"
  echo
  echo "=== audio services ==="
  service list 2>/dev/null | grep -i -E 'audio|bluetooth' || true
  echo
  echo "=== audio properties ==="
  getprop | grep -i -E 'audio|bluetooth|a2dp|hidl|aidl' || true
  echo
  echo "=== audio HAL libraries ==="
  for d in /vendor/lib64/hw /vendor/lib/hw /system/lib64/hw /system/lib/hw /odm/lib64/hw /odm/lib/hw; do
    [ -d "$d" ] || continue
    echo "-- $d"
    ls -la "$d" 2>/dev/null | grep -i audio || true
  done
  echo
  echo "=== audio policy/config files ==="
  find /vendor/etc /odm/etc /system/etc -maxdepth 3 -type f \( -iname '*audio*policy*.xml' -o -iname '*audio*.xml' -o -iname '*audio*.conf' \) 2>/dev/null | sort
  echo
  echo "=== framework features ==="
  pm list features 2>/dev/null | grep -i -E 'audio|bluetooth' || true
  echo
  echo "=== AudioFlinger ==="
  dumpsys media.audio_flinger 2>/dev/null || true
  echo
  echo "=== AudioPolicy ==="
  dumpsys media.audio_policy 2>/dev/null || dumpsys audio 2>/dev/null || true
} > "$OUT" 2>&1

chmod 0600 "$OUT"

HAL_STYLE="unknown"
if service list 2>/dev/null | grep -qi 'android.hardware.audio'; then
  HAL_STYLE="aidl-or-hidl"
fi
if ls /vendor/lib64/hw/audio.*.so /vendor/lib/hw/audio.*.so >/dev/null 2>&1; then
  HAL_STYLE="legacy-hw-module"
fi

DAEMON="false"
pidof wsa-btd >/dev/null 2>&1 && DAEMON="true"

cat > "$STATUS" <<EOF
{"installed":true,"daemon_running":$DAEMON,"hal_style":"$HAL_STYLE","audio_env":"$OUT","control_socket":"@wsa_bt_bridge","audio_socket":"@wsa_bt_audio"}
EOF
chmod 0600 "$STATUS"
