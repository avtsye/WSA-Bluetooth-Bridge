#!/system/bin/sh
ui_print "- WSA Bluetooth Bridge: selecting Audio HAL for device ABI"

ABI="$(getprop ro.product.cpu.abi)"
case "$ABI" in
  x86_64*)
    SRC="$MODPATH/hal/x86_64/audio.wsa_bridge.default.so"
    ;;
  arm64-v8a*)
    SRC="$MODPATH/hal/arm64-v8a/audio.wsa_bridge.default.so"
    ;;
  *)
    ui_print "! Unsupported ABI: $ABI"
    abort "Unsupported WSA ABI"
    ;;
esac

if [ ! -f "$SRC" ]; then
  abort "Audio HAL binary missing for $ABI"
fi

mkdir -p "$MODPATH/system/vendor/lib64/hw"
cp -f "$SRC" "$MODPATH/system/vendor/lib64/hw/audio.wsa_bridge.default.so"
chmod 0644 "$MODPATH/system/vendor/lib64/hw/audio.wsa_bridge.default.so"

set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/hal" 0 0 0755 0644
set_perm "$MODPATH/system/vendor/lib64/hw/audio.wsa_bridge.default.so" 0 0 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/audio-env.sh" 0 0 0755
set_perm "$MODPATH/policy-shim.sh" 0 0 0755
set_perm "$MODPATH/health-check.sh" 0 0 0755
set_perm "$MODPATH/enable-policy.sh" 0 0 0755
set_perm "$MODPATH/disable-policy.sh" 0 0 0755

ui_print "- Audio HAL installed for $ABI"
