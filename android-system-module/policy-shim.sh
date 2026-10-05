#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/local/tmp/wsa-bt-policy-state.json
LOG=/data/local/tmp/wsa-bt-bridge.log
WORK=/data/local/tmp/wsa-bt-policy
MARKER=/data/local/tmp/wsa-bt-enable-policy

mkdir -p "$WORK"

log() {
  echo "[policy-shim] $*" >> "$LOG"
}

find_policy() {
  for f in     /vendor/etc/audio_policy_configuration.xml     /odm/etc/audio_policy_configuration.xml     /system/etc/audio_policy_configuration.xml; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

POLICY="$(find_policy)"
if [ -z "$POLICY" ]; then
  log "No audio_policy_configuration.xml found; staying diagnostic-only"
  echo '{"compatible":false,"enabled":false,"reason":"policy_not_found"}' > "$STATE"
  exit 0
fi

RSM64=""
RSM32=""
for f in /vendor/lib64/hw/audio.r_submix.default.so /system/lib64/hw/audio.r_submix.default.so; do
  [ -f "$f" ] && RSM64="$f" && break
done
for f in /vendor/lib/hw/audio.r_submix.default.so /system/lib/hw/audio.r_submix.default.so; do
  [ -f "$f" ] && RSM32="$f" && break
done

if [ -z "$RSM64" ] && [ -z "$RSM32" ]; then
  log "Remote-submix HAL not present; cannot create safe secondary audio module"
  echo '{"compatible":false,"enabled":false,"reason":"remote_submix_missing"}' > "$STATE"
  exit 0
fi

cp -f "$POLICY" "$WORK/original.xml"

# This first deep-integration stage uses Android's existing remote-submix HAL as
# a safe secondary software audio endpoint. It does NOT replace the primary HAL.
# The bridge-specific binary transport remains in wsa-btd; a later adapter
# connects this endpoint to the PCM socket once the exact WSA HAL/API is known.
PATCHED="$WORK/patched.xml"
cp -f "$POLICY" "$PATCHED"

if grep -q 'name="wsa_bridge"' "$PATCHED"; then
  log "wsa_bridge module already present"
else
  # Insert a secondary module before the closing </modules>. The configuration
  # deliberately has no routes to the primary module, so failure cannot replace
  # WSA's normal speaker/mic path.
  awk '
    /<\/modules>/ && !done {
      print "        <module name=\"wsa_bridge\" halVersion=\"3.0\">"
      print "            <attachedDevices>"
      print "                <item>WsaBridge Out</item>"
      print "                <item>WsaBridge In</item>"
      print "            </attachedDevices>"
      print "            <defaultOutputDevice>WsaBridge Out</defaultOutputDevice>"
      print "            <mixPorts>"
      print "                <mixPort name=\"wsa_bridge output\" role=\"source\">"
      print "                    <profile name=\"\" format=\"AUDIO_FORMAT_PCM_16_BIT\" samplingRates=\"48000\" channelMasks=\"AUDIO_CHANNEL_OUT_STEREO\"/>"
      print "                </mixPort>"
      print "                <mixPort name=\"wsa_bridge input\" role=\"sink\">"
      print "                    <profile name=\"\" format=\"AUDIO_FORMAT_PCM_16_BIT\" samplingRates=\"48000\" channelMasks=\"AUDIO_CHANNEL_IN_MONO\"/>"
      print "                </mixPort>"
      print "            </mixPorts>"
      print "            <devicePorts>"
      print "                <devicePort tagName=\"WsaBridge Out\" type=\"AUDIO_DEVICE_OUT_REMOTE_SUBMIX\" role=\"sink\">"
      print "                    <profile name=\"\" format=\"AUDIO_FORMAT_PCM_16_BIT\" samplingRates=\"48000\" channelMasks=\"AUDIO_CHANNEL_OUT_STEREO\"/>"
      print "                </devicePort>"
      print "                <devicePort tagName=\"WsaBridge In\" type=\"AUDIO_DEVICE_IN_REMOTE_SUBMIX\" role=\"source\">"
      print "                    <profile name=\"\" format=\"AUDIO_FORMAT_PCM_16_BIT\" samplingRates=\"48000\" channelMasks=\"AUDIO_CHANNEL_IN_MONO\"/>"
      print "                </devicePort>"
      print "            </devicePorts>"
      print "            <routes>"
      print "                <route type=\"mix\" sink=\"WsaBridge Out\" sources=\"wsa_bridge output\"/>"
      print "                <route type=\"mix\" sink=\"wsa_bridge input\" sources=\"WsaBridge In\"/>"
      print "            </routes>"
      print "        </module>"
      done=1
    }
    { print }
  ' "$POLICY" > "$PATCHED.tmp" && mv "$PATCHED.tmp" "$PATCHED"
fi

# Validate basic XML shape before any overlay is prepared.
if ! grep -q '<audioPolicyConfiguration' "$PATCHED" || ! grep -q 'name="wsa_bridge"' "$PATCHED"; then
  log "Patched policy validation failed"
  echo '{"compatible":false,"enabled":false,"reason":"patch_validation_failed"}' > "$STATE"
  exit 0
fi

# Prepare a Magisk overlay path matching the discovered partition. It is not
# activated unless the explicit marker exists; this keeps first boot safe.
REL="${POLICY#/}"
OVERLAY="$MODDIR/system/${REL#vendor/}"
case "$POLICY" in
  /vendor/*) OVERLAY="$MODDIR/system/vendor/${POLICY#/vendor/}" ;;
  /odm/*)    OVERLAY="$MODDIR/system/odm/${POLICY#/odm/}" ;;
  /system/*) OVERLAY="$MODDIR/system/${POLICY#/system/}" ;;
esac

if [ ! -f "$MARKER" ]; then
  # Do not leave a live Magisk overlay behind before explicit activation.
  rm -f "$OVERLAY" 2>/dev/null || true
  log "Compatible policy detected; candidate prepared outside overlay tree"
  echo '{"compatible":true,"enabled":false,"reason":"awaiting_activation"}' > "$STATE"
  exit 0
fi

mkdir -p "$(dirname "$OVERLAY")"
cp -f "$PATCHED" "$OVERLAY"
log "Policy overlay copied into Magisk tree for next Android restart"
echo '{"compatible":true,"enabled":true,"reason":"overlay_prepared"}' > "$STATE"
exit 0
