#!/usr/bin/env swift
// Generates the kart sound effects (original, license-free):
//   engine.wav — seamless idle/drive loop · horn.wav — two-tone honk ·
//   skid.wav — drift noise burst.  Run:  swift scripts/generate-audio.swift
import AVFoundation

let sampleRate = 44_100.0

func writeWAV(_ samples: [Float], to path: String) {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let file = try! AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ])
    try! file.write(from: buffer)
    print("wrote \(path)")
}

var noiseSeed: UInt64 = 0xCAFE
func noise() -> Float {
    noiseSeed = noiseSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Float(Int64(truncatingIfNeeded: noiseSeed >> 33) % 1000) / 1000
}

// Engine: 0.6 s of 50+100 Hz saw with a noise floor — 30/60 whole cycles, so
// the loop seam is silent.
let engineCount = Int(0.6 * sampleRate)
var engine = [Float](repeating: 0, count: engineCount)
for i in 0..<engineCount {
    let t = Double(i) / sampleRate
    let saw50 = Float(2 * (t * 50).truncatingRemainder(dividingBy: 1) - 1)
    let saw100 = Float(2 * (t * 100).truncatingRemainder(dividingBy: 1) - 1)
    engine[i] = (saw50 * 0.5 + saw100 * 0.3 + noise() * 0.15) * 0.22
}
writeWAV(engine, to: "Project Cluster/Resources/engine.wav")

// Horn: 0.35 s two-tone with fast attack and a short tail.
let hornCount = Int(0.35 * sampleRate)
var horn = [Float](repeating: 0, count: hornCount)
for i in 0..<hornCount {
    let t = Double(i) / sampleRate
    let attack: Double = min(t / 0.01, 1)
    let tailStart: Double = max(0, t - 0.25)
    let release: Double = max(0, 1 - tailStart / 0.1)
    let envelope = Float(attack * release)
    let toneA: Double = tanh(sin(2 * Double.pi * 420 * t) * 3)
    let toneB: Double = tanh(sin(2 * Double.pi * 528 * t) * 3)
    horn[i] = Float(toneA + toneB) * 0.5 * envelope * 0.3
}
writeWAV(horn, to: "Project Cluster/Resources/horn.wav")

// Skid: 0.3 s of decaying noise.
let skidCount = Int(0.3 * sampleRate)
var skid = [Float](repeating: 0, count: skidCount)
var lowpass: Float = 0
for i in 0..<skidCount {
    let t = Float(i) / Float(skidCount)
    lowpass += (noise() - lowpass) * 0.4
    skid[i] = lowpass * (1 - t) * (1 - t) * 0.3
}
writeWAV(skid, to: "Project Cluster/Resources/skid.wav")
