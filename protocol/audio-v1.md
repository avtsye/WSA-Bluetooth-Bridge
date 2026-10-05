# Headset Audio Protocol

This document defines the binary/audio extension to the existing control JSONL protocol.

## Control messages

### List audio routes

```json
{"type":"audio.routes"}
```

Response includes render and capture endpoints.

### Select route

```json
{
  "type":"audio.route.select",
  "renderEndpointId":"...",
  "captureEndpointId":"..."
}
```

### Start playback stream

```json
{
  "type":"audio.playback.start",
  "sampleRate":48000,
  "channels":2,
  "sampleFormat":"s16le"
}
```

### Stop playback stream

```json
{"type":"audio.playback.stop"}
```

### Start microphone capture

```json
{
  "type":"audio.capture.start",
  "sampleRate":16000,
  "channels":1,
  "sampleFormat":"s16le"
}
```

### Stop microphone capture

```json
{"type":"audio.capture.stop"}
```

## PCM framing

PCM frames will use a dedicated binary stream rather than base64 JSON.

Initial frame header:

```text
magic      4 bytes   "WSAB"
version    u8
stream     u8        1=playback, 2=capture
flags      u16
length     u32 LE
sequence   u32 LE
payload    <length bytes>
```

The control channel remains JSONL. Audio payloads use a separate local socket/channel so log/control traffic cannot block real-time audio.

## Reliability

- Playback uses bounded jitter buffering.
- Capture drops oldest frames rather than blocking the Windows capture callback.
- Route loss generates an immediate control event.
- Stream sequence numbers allow diagnostics for dropped frames.
