//
//  AuxSoundFallback.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
@preconcurrency import AVFoundation
import os.log

/// Tiny tone generator used as a last-resort *audible* backup when AlarmKit alerts on very short leads.
/// Plays a looping beep pattern for up to `maxSeconds`, or until `stop()` is called.
/// Strict-concurrency safe for Swift 6 (no Sendable captures in callbacks).
@MainActor
final class AuxSoundFallback {
    static let shared = AuxSoundFallback()

    private let log = Logger(subsystem: "com.hodlsimulator.alarmstacks", category: "AuxSound")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var isPrepared = false
    private(set) var isPlaying = false

    private init() { }

    func startIfNeeded(maxSeconds: Int = 15,
                       frequency: Double = 880.0,
                       onMillis: Int = 250,
                       offMillis: Int = 250,
                       amplitude: Float = 0.6) {
        guard isPlaying == false else { return }
        do {
            try prepareSession()
            try prepareEngineIfNeeded()

            // Build a single pattern buffer (tone + silence) and loop it — no completion closures.
            let format = engine.outputNode.outputFormat(forBus: 0)
            let pattern = makePatternBuffer(frequency: frequency,
                                            amplitude: amplitude,
                                            onMillis: onMillis,
                                            offMillis: offMillis,
                                            format: format)

            player.play()
            player.scheduleBuffer(pattern, at: nil, options: [.loops], completionHandler: nil)

            isPlaying = true
            log.info("Aux tone started (max \(maxSeconds)s, \(frequency, privacy: .public)Hz, on \(onMillis)ms / off \(offMillis)ms)")

            // Auto stop after maxSeconds without capturing self across actors.
            let secs = max(1, maxSeconds)
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
                await MainActor.run { AuxSoundFallback.shared.stop() }
            }
        } catch {
            log.error("Aux tone start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        player.stop()
        engine.pause()
        deactivateSession()
        isPlaying = false
        log.info("Aux tone stopped")
    }

    // MARK: - Internals

    private func prepareSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback; duck others so we don't blast over running audio completely.
        try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try session.setActive(true, options: [])
    }

    private func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func prepareEngineIfNeeded() throws {
        guard isPrepared == false else { return }
        engine.attach(player)
        let fmt = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.prepare()
        try engine.start()
        isPrepared = true
    }

    /// Create a single buffer containing [tone | silence], which we loop with `.loops`.
    private func makePatternBuffer(frequency: Double,
                                   amplitude: Float,
                                   onMillis: Int,
                                   offMillis: Int,
                                   format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let onFrames  = Int((Double(onMillis)  / 1000.0) * sr)
        let offFrames = Int((Double(offMillis) / 1000.0) * sr)
        let totalFrames = onFrames + offFrames

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        guard let channels = buffer.floatChannelData else {
            // Fallback: if channel data is unavailable, just return an empty (silence) buffer.
            return buffer
        }

        let channelCount = Int(format.channelCount)
        let twoPiF = 2.0 * Double.pi * frequency

        // Fill tone portion
        for ch in 0..<channelCount {
            let dst = channels[ch]
            var t = 0.0
            for i in 0..<onFrames {
                t = Double(i) / sr
                dst[i] = Float(sin(twoPiF * t)) * amplitude
            }
            // Fill silence portion
            if offFrames > 0 {
                for i in 0..<offFrames {
                    dst[onFrames + i] = 0.0
                }
            }
        }

        return buffer
    }
}

