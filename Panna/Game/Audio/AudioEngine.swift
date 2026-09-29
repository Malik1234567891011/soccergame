import AVFoundation

enum Sfx: CaseIterable {
    case kick, bigKick, header, whistle, whistleLong, net, goalHorn, save, tackle, slide, wall, post, perfect, panna, ankles, skill, flow, hypeReady
    case uiTap, uiConfirm, uiBack, reward, packOpen, revealRare, revealEpic, revealLegend, levelUp, coin
}

/// Everything is synthesised at launch — no audio assets to ship or license.
final class AudioEngine {
    static let shared = AudioEngine()
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var buffers: [Sfx: AVAudioPCMBuffer] = [:]
    private var pool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private let crowdNode = AVAudioPlayerNode()
    private let musicNode = AVAudioPlayerNode()
    private let crowdMixer = AVAudioMixerNode()
    private var crowdBase: Float = 0.25
    private var started = false
    var sfxVolume: Float = 1 { didSet { pool.forEach { $0.volume = sfxVolume } } }
    var musicVolume: Float = 0.5 { didSet { musicNode.volume = musicVolume } }
    private var musicBuffer: AVAudioPCMBuffer?
    private var crowdBuffer: AVAudioPCMBuffer?

    private init() {}

    /// PANNA_MUTE=1 silences everything (used for simulator test runs).
    let muted = ProcessInfo.processInfo.environment["PANNA_MUTE"] != nil

    func start() {
        guard !started, !muted else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<14 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            pool.append(n)
        }
        engine.attach(crowdNode)
        engine.attach(crowdMixer)
        engine.connect(crowdNode, to: crowdMixer, format: format)
        engine.connect(crowdMixer, to: engine.mainMixerNode, format: format)
        engine.attach(musicNode)
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        crowdMixer.outputVolume = 0
        musicNode.volume = musicVolume
        DispatchQueue.global(qos: .userInitiated).async {
            var synth = Synth()
            var b: [Sfx: AVAudioPCMBuffer] = [:]
            for s in Sfx.allCases { b[s] = self.buffer(synth.make(s)) }
            let crowd = self.buffer(synth.crowdLoop())
            let music = self.buffer(synth.musicLoop())
            DispatchQueue.main.async {
                self.buffers = b
                self.crowdBuffer = crowd
                self.musicBuffer = music
                do { try self.engine.start() } catch { print("audio engine failed: \(error)") }
                self.pool.forEach { $0.play() }
                self.crowdNode.play()
                self.musicNode.play()
                if let c = crowd { self.crowdNode.scheduleBuffer(c, at: nil, options: .loops) }
                if self.wantMusic, let m = music { self.musicNode.scheduleBuffer(m, at: nil, options: .loops) }
            }
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        for i in 0..<samples.count { l[i] = samples[i]; r[i] = samples[i] }
        return buf
    }

    func play(_ s: Sfx, volume: Float = 1, pitch: Float = 1) {
        guard started, let b = buffers[s], !pool.isEmpty, engine.isRunning else { return }
        let n = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        n.volume = volume * sfxVolume
        n.scheduleBuffer(b, at: nil, options: .interrupts)
        if !n.isPlaying { n.play() }
    }

    // MARK: Crowd

    func setCrowd(_ on: Bool, base: Float = 0.25) {
        crowdBase = base
        fade(to: on ? base : 0, duration: 0.8)
    }

    func crowdSwell(_ amount: Float) {
        let peak = min(1, crowdBase + amount * 0.75)
        crowdMixer.outputVolume = peak
        fade(to: crowdBase, duration: 2.5, delay: 0.4)
    }

    private var fadeTimer: Timer?
    private func fade(to target: Float, duration: Double, delay: Double = 0) {
        fadeTimer?.invalidate()
        let start = crowdMixer.outputVolume
        let t0 = Date().addingTimeInterval(delay)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let el = Date().timeIntervalSince(t0)
            if el < 0 { return }
            let k = Float(min(1, el / duration))
            self.crowdMixer.outputVolume = start + (target - start) * k
            if k >= 1 { t.invalidate() }
        }
    }

    // MARK: Music

    private var wantMusic = true
    func setMusic(_ on: Bool) {
        wantMusic = on
        guard started else { return }
        if on {
            if !musicNode.isPlaying || musicNode.volume == 0 {
                musicNode.stop()
                if let m = musicBuffer { musicNode.scheduleBuffer(m, at: nil, options: .loops) }
                musicNode.play()
            }
            musicNode.volume = musicVolume
        } else {
            musicNode.volume = 0
        }
    }
}

/// Tiny DSP toolkit.
private struct Synth {
    let sr: Float = 44100
    var seed: UInt32 = 12345

    mutating func noise() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(seed >> 8) / Float(1 << 24) * 2 - 1
    }

    func env(_ t: Float, a: Float, d: Float) -> Float {
        if t < a { return t / a }
        return exp(-(t - a) / d)
    }

    func make(_ s: Sfx) -> [Float] {
        var me = self
        switch s {
        case .kick: return me.thump(freq: 110, drop: 60, dur: 0.18, click: 0.5, gain: 0.8)
        case .bigKick: return me.thump(freq: 95, drop: 50, dur: 0.3, click: 0.9, gain: 1.0)
        case .header: return me.thump(freq: 180, drop: 90, dur: 0.14, click: 0.3, gain: 0.7)
        case .tackle: return me.thump(freq: 70, drop: 35, dur: 0.25, click: 0.3, gain: 0.9, noiseAmt: 0.5)
        case .slide: return me.swish(dur: 0.45, lo: 0.02, hi: 0.2, gain: 0.5)
        case .wall: return me.thump(freq: 60, drop: 30, dur: 0.35, click: 0.7, gain: 0.8, noiseAmt: 0.6)
        case .post: return me.bell(freqs: [880, 1320, 2220], dur: 0.9, gain: 0.5)
        case .net: return me.swish(dur: 0.6, lo: 0.05, hi: 0.35, gain: 0.7)
        case .whistle: return me.whistle(dur: 0.35)
        case .whistleLong: return me.whistle(dur: 0.25) + [Float](repeating: 0, count: 3000) + me.whistle(dur: 0.25) + [Float](repeating: 0, count: 3000) + me.whistle(dur: 0.8)
        case .goalHorn: return me.horn(dur: 1.2)
        case .save: return me.thump(freq: 140, drop: 80, dur: 0.2, click: 0.8, gain: 0.8)
        case .perfect: return me.arp([784, 988, 1175, 1568], step: 0.05, dur: 0.5, gain: 0.35)
        case .panna: return me.mix(me.swish(dur: 0.5, lo: 0.1, hi: 0.5, gain: 0.5), me.arp([523, 659, 784, 1047, 1319], step: 0.045, dur: 0.7, gain: 0.35))
        case .ankles: return me.mix(me.swish(dur: 0.4, lo: 0.2, hi: 0.6, gain: 0.4), me.arp([392, 494, 587, 784], step: 0.04, dur: 0.5, gain: 0.3))
        case .skill: return me.swish(dur: 0.22, lo: 0.2, hi: 0.6, gain: 0.35)
        case .flow: return me.mix(me.riser(dur: 0.9, gain: 0.5), me.arp([262, 330, 392, 523, 659, 784], step: 0.06, dur: 1.0, gain: 0.3))
        case .hypeReady: return me.arp([659, 988], step: 0.08, dur: 0.4, gain: 0.3)
        case .uiTap: return me.click(freq: 1800, dur: 0.04, gain: 0.25)
        case .uiConfirm: return me.arp([660, 990], step: 0.05, dur: 0.2, gain: 0.25)
        case .uiBack: return me.arp([660, 440], step: 0.05, dur: 0.18, gain: 0.2)
        case .reward: return me.arp([523, 659, 784, 1047], step: 0.07, dur: 0.6, gain: 0.3)
        case .coin: return me.arp([1319, 1760], step: 0.04, dur: 0.18, gain: 0.2)
        case .levelUp: return me.arp([392, 523, 659, 784, 1047, 1319], step: 0.08, dur: 1.0, gain: 0.35)
        case .packOpen: return me.mix(me.riser(dur: 1.4, gain: 0.45), me.swish(dur: 1.4, lo: 0.02, hi: 0.3, gain: 0.25))
        case .revealRare: return me.arp([523, 784], step: 0.08, dur: 0.6, gain: 0.35)
        case .revealEpic: return me.mix(me.arp([440, 554, 659, 880, 1109], step: 0.07, dur: 1.0, gain: 0.35), me.thump(freq: 60, drop: 30, dur: 0.6, click: 0.5, gain: 0.8))
        case .revealLegend: return me.mix(me.horn(dur: 1.6), me.mix(me.arp([392, 494, 587, 784, 988, 1175, 1568], step: 0.09, dur: 1.8, gain: 0.35), me.thump(freq: 50, drop: 25, dur: 1.0, click: 0.8, gain: 1.0)))
        }
    }

    func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: max(a.count, b.count))
        for i in 0..<a.count { out[i] += a[i] }
        for i in 0..<b.count { out[i] += b[i] }
        return out
    }

    mutating func thump(freq: Float, drop: Float, dur: Float, click: Float, gain: Float, noiseAmt: Float = 0.2) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var ph: Float = 0
        var lp: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            let f = drop + (freq - drop) * exp(-t * 25)
            ph += 2 * .pi * f / sr
            let body = sin(ph) * exp(-t / (dur * 0.35))
            let nz = noise()
            lp += (nz - lp) * 0.3
            let clk = nz * click * exp(-t * 180)
            out[i] = (body * 0.9 + lp * noiseAmt * exp(-t * 30) + clk) * gain
        }
        return out
    }

    mutating func swish(dur: Float, lo: Float, hi: Float, gain: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var lp: Float = 0, bp: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let cutoff = lo + (hi - lo) * sin(t * .pi)
            let x = noise()
            lp += (x - lp) * cutoff
            bp += (lp - bp) * cutoff * 0.5
            out[i] = (lp - bp) * sin(t * .pi) * gain * 2
        }
        return out
    }

    func whistle(dur: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var ph: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            let f: Float = 2900 + sin(t * 2 * .pi * 28) * 90
            ph += 2 * .pi * f / sr
            let e = min(1, t * 60) * min(1, (dur - t) * 30)
            out[i] = (sin(ph) + 0.3 * sin(ph * 2)) * 0.22 * e
        }
        return out
    }

    func horn(dur: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        let freqs: [Float] = [233, 294, 349]
        var phs: [Float] = [0, 0, 0]
        for i in 0..<n {
            let t = Float(i) / sr
            var v: Float = 0
            for k in 0..<3 {
                phs[k] += freqs[k] / sr
                let saw = 2 * (phs[k] - floor(phs[k])) - 1
                v += saw
            }
            let e = min(1, t * 15) * min(1, (dur - t) * 4)
            out[i] = tanh(v * 0.6) * 0.3 * e
        }
        return out
    }

    func bell(freqs: [Float], dur: Float, gain: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / sr
            var v: Float = 0
            for (k, f) in freqs.enumerated() { v += sin(2 * .pi * f * t) * exp(-t * Float(4 + k * 3)) }
            out[i] = v * gain / Float(freqs.count)
        }
        return out
    }

    func arp(_ notes: [Float], step: Float, dur: Float, gain: Float) -> [Float] {
        let n = Int((dur + step * Float(notes.count)) * sr)
        var out = [Float](repeating: 0, count: n)
        for (k, f) in notes.enumerated() {
            let start = Int(Float(k) * step * sr)
            for i in 0..<Int(dur * sr) where start + i < n {
                let t = Float(i) / sr
                let e = min(1, t * 200) * exp(-t / (dur * 0.4))
                out[start + i] += (sin(2 * .pi * f * t) + 0.35 * sin(4 * .pi * f * t)) * e * gain
            }
        }
        return out
    }

    mutating func riser(dur: Float, gain: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var lp: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            lp += (noise() - lp) * (0.02 + t * 0.4)
            out[i] = lp * t * t * gain * 2
        }
        return out
    }

    func click(freq: Float, dur: Float, gain: Float) -> [Float] {
        let n = Int(dur * sr)
        return (0..<n).map { i in
            let t = Float(i) / sr
            return sin(2 * .pi * freq * t) * exp(-t * 90) * gain
        }
    }

    /// Crowd bed: layered band-passed noise with slow swells and occasional chants.
    mutating func crowdLoop() -> [Float] {
        let dur: Float = 6
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        var lp1: Float = 0, lp2: Float = 0, lp3: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            let x = noise()
            lp1 += (x - lp1) * 0.08
            lp2 += (lp1 - lp2) * 0.08
            lp3 += (x - lp3) * 0.25
            let mod = 0.75 + 0.25 * sin(t * 2 * .pi / dur * 2) * sin(t * 2 * .pi / dur * 3 + 1)
            out[i] = ((lp1 - lp2) * 3.0 + (lp3 - lp1) * 0.6) * mod * 0.5
        }
        // Crossfade the loop seam.
        let fadeN = Int(0.3 * sr)
        for i in 0..<fadeN {
            let k = Float(i) / Float(fadeN)
            out[i] = out[i] * k + out[n - fadeN + i] * (1 - k)
        }
        return Array(out[0..<(n - fadeN)])
    }

    /// Menu beat: 140 BPM half-time street groove, 8 bars.
    mutating func musicLoop() -> [Float] {
        let bpm: Float = 140
        let beat = 60 / bpm
        let bars = 8
        let n = Int(Float(bars * 4) * beat * sr)
        var out = [Float](repeating: 0, count: n)
        func add(_ s: [Float], at time: Float, gain: Float) {
            let start = Int(time * sr)
            for i in 0..<s.count where start + i < n { out[start + i] += s[i] * gain }
        }
        let kick = thump(freq: 120, drop: 42, dur: 0.4, click: 0.4, gain: 1.0, noiseAmt: 0)
        var snare = swish(dur: 0.22, lo: 0.3, hi: 0.8, gain: 0.8)
        snare = mix(snare, thump(freq: 200, drop: 160, dur: 0.12, click: 0.2, gain: 0.4, noiseAmt: 0))
        let hat = swish(dur: 0.04, lo: 0.7, hi: 0.95, gain: 0.35)
        let chords: [[Float]] = [[220, 261.6, 329.6], [174.6, 220, 261.6], [196, 246.9, 293.7], [164.8, 207.7, 246.9]]
        let bassNotes: [Float] = [55, 43.65, 49, 41.2]
        for bar in 0..<bars {
            let t0 = Float(bar * 4) * beat
            // Drums (half-time: snare on 3).
            add(kick, at: t0, gain: 0.9)
            add(kick, at: t0 + beat * 1.75, gain: 0.6)
            if bar % 2 == 1 { add(kick, at: t0 + beat * 2.5, gain: 0.55) }
            add(snare, at: t0 + beat * 2, gain: 0.7)
            for h in 0..<8 {
                let roll = bar % 4 == 3 && h >= 6
                add(hat, at: t0 + Float(h) * beat / 2, gain: h % 2 == 0 ? 0.5 : 0.3)
                if roll { add(hat, at: t0 + Float(h) * beat / 2 + beat / 4, gain: 0.3) }
            }
            // Pad chord.
            let ch = chords[(bar / 2) % chords.count]
            let len = Int(beat * 4 * sr)
            let start = Int(t0 * sr)
            for i in 0..<len where start + i < n {
                let t = Float(i) / sr
                var v: Float = 0
                for f in ch { v += sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 2.003 * t) }
                let e = min(1, t * 4) * min(1, (beat * 4 - t) * 4)
                out[start + i] += v * 0.028 * e
            }
            // Sub bass (808-ish).
            let bf = bassNotes[(bar / 2) % bassNotes.count]
            for hit in [Float(0), 1.75, 2.5] {
                let bs = Int((t0 + hit * beat) * sr)
                for i in 0..<Int(beat * 0.9 * sr) where bs + i < n {
                    let t = Float(i) / sr
                    out[bs + i] += sin(2 * .pi * bf * t) * exp(-t * 2.2) * 0.35
                }
            }
            // Pluck melody.
            let mel: [Float] = [659, 784, 880, 784, 659, 587, 523, 587]
            if bar >= 2 {
                for (k, f) in mel.enumerated() where (k + bar) % 3 != 0 {
                    let st = Int((t0 + Float(k) * beat / 2) * sr)
                    for i in 0..<Int(0.25 * sr) where st + i < n {
                        let t = Float(i) / sr
                        out[st + i] += sin(2 * .pi * f * t) * exp(-t * 14) * 0.08
                    }
                }
            }
        }
        // Soft clip.
        return out.map { tanh($0 * 1.2) * 0.8 }
    }
}
