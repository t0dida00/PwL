import AVFoundation
import Observation

/// Background music for games. Music is synthesized in code (no audio assets).
/// Games call `setMusicActive(true)` on appear / resume and `false` on pause / disappear;
/// the user's on/off preference (`isMusicOn`) is persisted.
@MainActor
@Observable
final class AudioManager {
    private static let musicKey = "pwl.musicOn"

    var isMusicOn: Bool {
        didSet {
            UserDefaults.standard.set(isMusicOn, forKey: Self.musicKey)
            updatePlayback()
        }
    }

    @ObservationIgnored private var wantsMusic = false
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let synth = MusicBoxSynth()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?

    init() {
        isMusicOn = UserDefaults.standard.object(forKey: Self.musicKey) as? Bool ?? true
    }

    func toggleMusic() {
        isMusicOn.toggle()
    }

    func setMusicActive(_ active: Bool) {
        wantsMusic = active
        updatePlayback()
    }

    private func updatePlayback() {
        if isMusicOn && wantsMusic {
            start()
        } else if engine.isRunning {
            engine.pause()
        }
    }

    private func start() {
        configureIfNeeded()
        guard !engine.isRunning else { return }
        do {
            // .ambient mixes with other audio and respects the silent switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            print("AudioManager: failed to start engine: \(error)")
        }
    }

    private func configureIfNeeded() {
        guard sourceNode == nil else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        synth.prepare(sampleRate: sampleRate)
        let node = Self.makeSourceNode(synth: synth, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        sourceNode = node
    }

    /// `nonisolated` so the render closure is not MainActor-isolated —
    /// it runs on the real-time audio thread.
    nonisolated private static func makeSourceNode(synth: MusicBoxSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            synth.render(frameCount: frameCount, bufferList: bufferList)
        }
    }
}

/// A tiny music-box style synthesizer: a looping arpeggio over four chords.
/// Only touched from the audio render thread after `prepare`.
final class MusicBoxSynth: @unchecked Sendable {
    private struct Voice {
        var frequency = 0.0
        var phase = 0.0
        var envelope = 0.0
        var attack = 0.0
    }

    private var sampleRate = 44_100.0
    private var voices = Array(repeating: Voice(), count: 8)
    private var nextVoice = 0
    private var samplesUntilNextStep = 0
    private var step = 0
    private var decayPerSample = 0.9999
    private var attackPerSample = 0.01
    private let stepDuration = 0.3
    private let steps: [[Double]]

    init() {
        steps = Self.makeSong()
    }

    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        decayPerSample = pow(0.001, 1.0 / (sampleRate * 1.4))
        attackPerSample = 1.0 / (sampleRate * 0.008)
    }

    func render(frameCount: AVAudioFrameCount, bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let stepSamples = Int(sampleRate * stepDuration)
        let twoPi = 2.0 * Double.pi

        for frame in 0..<Int(frameCount) {
            if samplesUntilNextStep <= 0 {
                for frequency in steps[step % steps.count] { trigger(frequency) }
                step += 1
                samplesUntilNextStep = stepSamples
            }
            samplesUntilNextStep -= 1

            var sample = 0.0
            for index in voices.indices where voices[index].frequency > 0 {
                var voice = voices[index]
                voice.attack = min(1, voice.attack + attackPerSample)
                let tone = sin(voice.phase) + 0.25 * sin(2 * voice.phase) + 0.08 * sin(3 * voice.phase)
                sample += tone * voice.envelope * voice.attack
                voice.phase += twoPi * voice.frequency / sampleRate
                if voice.phase > twoPi { voice.phase -= twoPi }
                voice.envelope *= decayPerSample
                voices[index] = voice
            }

            let value = Float(sample * 0.1)
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
            }
        }
        return noErr
    }

    private func trigger(_ frequency: Double) {
        voices[nextVoice] = Voice(frequency: frequency, phase: 0, envelope: 1, attack: 0)
        nextVoice = (nextVoice + 1) % voices.count
    }

    private static func makeSong() -> [[Double]] {
        func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        // Cmaj7 – Am7 – Fmaj7 – G6, arpeggiated an octave up with a bass note on each chord.
        let chords = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 64]]
        let pattern = [0, 2, 1, 3, 2, 1, 3, 2]
        var song: [[Double]] = []
        for chord in chords {
            for (index, noteIndex) in pattern.enumerated() {
                var notes = [hz(chord[noteIndex] + 12)]
                if index == 0 { notes.append(hz(chord[0] - 12)) }
                song.append(notes)
            }
        }
        return song
    }
}
