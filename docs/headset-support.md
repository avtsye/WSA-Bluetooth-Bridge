# Full Bluetooth Headset Support

The project target is no longer a BLE-only bridge. The headset path is intended to behave as a persistent Android system capability.

## Target behavior

A Bluetooth headset connected through Windows should be usable inside WSA for:

- Media playback (A2DP-equivalent behavior)
- Microphone capture / headset mode (HFP/HSP-equivalent behavior)
- Volume and media control events (AVRCP-equivalent behavior)
- Connect/disconnect state
- Automatic reconnect
- Multiple audio endpoints
- App-transparent playback and recording
- Simultaneous BLE/GATT access for accessory features when the same device exposes them

## Architecture

```
Android apps
   |
   +--> AudioTrack / MediaPlayer / ExoPlayer
   |          |
   |          v
   |     Android AudioFlinger
   |          |
   |          v
   |   WSA virtual audio backend
   |          |
   |          +---------------------------+
   |                                      |
   +--> AudioRecord                        |
              |                            |
              v                            |
       Android AudioFlinger                |
              |                            |
              v                            |
       WSA virtual capture backend         |
              |                            |
              +-------------+--------------+
                            |
                         wsa-btd
                            |
                     bridge transport
                            |
                 WsaBluetoothHost.exe
                   |                |
                   v                v
             Windows render     Windows capture
                   |                |
                   +-------+--------+
                           |
                    Bluetooth headset
```

Windows remains responsible for the physical Bluetooth profiles. Android receives stable virtual playback/capture devices backed by that connection.

## Milestones

### H1 — Host duplex audio
- Enumerate Windows render and capture endpoints.
- Select an output and matching microphone.
- Send PCM to a selected render endpoint.
- Capture PCM from a selected microphone.
- Report endpoint state changes.

### H2 — Bridge duplex protocol
- Versioned PCM stream framing.
- Playback start/stop.
- Capture start/stop.
- Flow control and bounded buffering.
- Device state and route events.

### H3 — Android system audio bridge
- Native WSA-side daemon.
- Playback sink for Android PCM.
- Capture source for Android PCM.
- Boot-time startup.

### H4 — Android audio integration
- Expose virtual output/input to AudioFlinger.
- Route normal AudioTrack/AudioRecord through the bridge.
- Make ordinary Android apps work without bridge-specific APIs.

### H5 — Headset profile behavior
- Headset/media mode switching.
- Volume synchronization.
- Play/pause/next/previous media events.
- Connection loss and automatic reconnect.
- Route changes while apps are active.

### H6 — Bluetooth framework integration
- Surface headset connection state to Android's Bluetooth/audio framework where practical.
- Integrate BLE/GATT device identity with the matching audio route.
- Remove dependency on the diagnostic APK for normal use.

## Definition of done

The project is considered headset-complete when an unmodified Android app inside WSA can:

1. Play audio to the Bluetooth headset.
2. Record from the headset microphone.
3. Survive headset disconnect/reconnect.
4. Switch between media and microphone use.
5. Receive media-control behavior without bridge-specific code.
6. Use the headset across multiple Android apps after one-time system installation.
