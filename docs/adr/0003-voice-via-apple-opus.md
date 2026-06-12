# ADR 0003 — Voice codec: Apple's native Opus (AVAudioConverter), no vendored libopus

**Date:** 2026-06-12 · **Status:** accepted · **Phase:** 3

## Context

PLAN §8 called for Opus and said: evaluate `AVAudioConverter`'s native support first, vendor libopus
as the dependable fallback. Probed empirically on macOS 26 (scripted, 440 Hz sine through
`kAudioFormatOpus`): **encode works** (960 samples → 125 B at 40 kbps) and **decode works**
(returns audio with expected energy; first call returns slightly fewer samples due to decoder
priming — normal Opus behavior).

## Decision

`ClusterVoice` uses `AVAudioConverter` with `kAudioFormatOpus` for both encode and decode.
No third-party audio dependency. The dependency count of the entire app stays at two (GRDB,
SwiftNIO-on-the-relay).

Packet-loss concealment: CoreAudio's Opus decoder doesn't expose libopus's PLC/FEC API, so the
jitter buffer conceals gaps by replaying the previous frame at reduced gain, then silence. Voice
frames are mic-gated at the sender anyway (silence is never sent), so concealment only covers
genuine network loss.

## Consequences

- If a future platform/OS regression breaks the native codec, the fallback remains what it always
  was: vendor libopus behind the same `OpusEncoder`/`OpusDecoder` interface.
- iOS reuses this unchanged (same framework, same format).
- Encoder/decoder instances are stateful per stream: one encoder (the mic), one decoder per remote
  speaker, owned by their playback pipeline.
