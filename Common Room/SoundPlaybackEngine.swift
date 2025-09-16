//
//  SoundPlaybackEngine.swift
//  Common Room
//
//  Created by duck on 16/09/2025.
//

import AVFoundation
import Combine
import Foundation

/// Coordinates AVAudioPlayer instances for each ambient sound.
final class SoundPlaybackManager: ObservableObject {
    @Published private var playingSoundIDs: Set<AmbientSound.ID> = []
    @Published private(set) var sliderVolumes: [AmbientSound.ID: Float]
    @Published private(set) var intervalDurations: [AmbientSound.ID: TimeInterval]
    @Published var isMuted: Bool

    private var players: [AmbientSound.ID: AVAudioPlayer] = [:]
    private var timers: [AmbientSound.ID: Timer] = [:]
    private var lastVariantIndices: [AmbientSound.ID: Int] = [:]

    init(sounds: [AmbientSound],
         initialVolumes: [AmbientSound.ID: Float] = [:],
         initialIntervals: [AmbientSound.ID: TimeInterval] = [:],
         initialMute: Bool = false) {
        sliderVolumes = Dictionary(uniqueKeysWithValues: sounds.map { sound in
            let stored = initialVolumes[sound.id] ?? 1.0
            let clamped = min(max(stored, 0), 1)
            return (sound.id, clamped)
        })
        intervalDurations = Dictionary(uniqueKeysWithValues: sounds.compactMap { sound in
            guard let configuration = sound.intervalConfiguration else { return nil }
            let stored = initialIntervals[sound.id] ?? configuration.defaultInterval
            let clamped = min(max(stored, configuration.range.lowerBound), configuration.range.upperBound)
            return (sound.id, clamped)
        })
        isMuted = initialMute
        configureAudioSession()
    }

    convenience init() {
        self.init(sounds: [])
    }

    // MARK: - Public API

    func isPlaying(_ sound: AmbientSound) -> Bool {
        playingSoundIDs.contains(sound.id)
    }

    func toggle(_ sound: AmbientSound) {
        if isPlaying(sound) {
            stop(sound)
        } else {
            play(sound)
        }
    }

    func volume(for sound: AmbientSound) -> Float {
        sliderVolumes[sound.id] ?? 1.0
    }

    func setVolume(_ value: Float, for sound: AmbientSound) {
        let clamped = min(max(value, 0), 1)
        sliderVolumes[sound.id] = clamped
        applyVolume(clamped, to: sound)
    }

    func interval(for sound: AmbientSound) -> TimeInterval {
        intervalDurations[sound.id] ?? sound.intervalConfiguration?.defaultInterval ?? 30
    }

    func setInterval(_ value: TimeInterval, for sound: AmbientSound) {
        guard let configuration = sound.intervalConfiguration else { return }

        let clampedValue = min(max(value, configuration.range.lowerBound), configuration.range.upperBound)
        intervalDurations[sound.id] = clampedValue

        guard isPlaying(sound) else { return }
        scheduleTimer(for: sound)
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        refreshActivePlayerVolumes()
    }

    // MARK: - Playback

    private func play(_ sound: AmbientSound) {
        switch sound.playback {
        case let .looping(file):
            guard let player = loopingPlayer(for: sound, fileName: file) else { return }
            player.currentTime = 0
            player.setVolume(effectiveVolume(for: sound), fadeDuration: 0)

            if player.play() {
                playingSoundIDs.insert(sound.id)
            } else {
                playingSoundIDs.remove(sound.id)
            }

        case .intervalRandom:
            guard playRandomVariant(for: sound) else {
                playingSoundIDs.remove(sound.id)
                return
            }
            playingSoundIDs.insert(sound.id)
            scheduleTimer(for: sound)
        }
    }

    private func stop(_ sound: AmbientSound) {
        timers[sound.id]?.invalidate()
        timers.removeValue(forKey: sound.id)

        if let player = players[sound.id] {
            player.stop()
            player.currentTime = 0
        }

        players.removeValue(forKey: sound.id)
        lastVariantIndices.removeValue(forKey: sound.id)
        playingSoundIDs.remove(sound.id)
    }

    private func loopingPlayer(for sound: AmbientSound, fileName: String) -> AVAudioPlayer? {
        if let existing = players[sound.id] {
            return existing
        }

        guard let player = makePlayer(for: sound, fileName: fileName) else { return nil }
        player.numberOfLoops = -1
        players[sound.id] = player
        return player
    }

    private func applyVolume(_ value: Float, to sound: AmbientSound) {
        guard let player = players[sound.id] else { return }
        player.setVolume(isMuted ? 0 : value, fadeDuration: 0)
    }

    @discardableResult
    private func playRandomVariant(for sound: AmbientSound) -> Bool {
        players[sound.id]?.stop()

        guard let fileName = nextVariantName(for: sound),
              let player = makePlayer(for: sound, fileName: fileName) else {
            return false
        }

        player.numberOfLoops = 0
        player.currentTime = 0
        player.setVolume(effectiveVolume(for: sound), fadeDuration: 0)
        players[sound.id] = player
        player.play()
        return true
    }

    private func scheduleTimer(for sound: AmbientSound) {
        timers[sound.id]?.invalidate()

        guard let interval = intervalDurations[sound.id] ?? sound.intervalConfiguration?.defaultInterval else {
            return
        }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard self.playingSoundIDs.contains(sound.id) else { return }

            if self.playRandomVariant(for: sound) {
                self.scheduleTimer(for: sound)
            } else {
                self.stop(sound)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        timers[sound.id] = timer
    }

    private func nextVariantName(for sound: AmbientSound) -> String? {
        let files = sound.availableFiles
        guard !files.isEmpty else { return nil }

        if files.count == 1 {
            lastVariantIndices[sound.id] = 0
            return files.first
        }

        let indices = Array(files.indices)
        let last = lastVariantIndices[sound.id]
        let candidates = indices.filter { $0 != last }

        guard let nextIndex = candidates.randomElement() else { return nil }
        lastVariantIndices[sound.id] = nextIndex
        return files[nextIndex]
    }

    private func makePlayer(for sound: AmbientSound, fileName: String) -> AVAudioPlayer? {
        guard let url = SoundPlaybackManager.resolveURL(for: fileName, withExtension: sound.fileExtension) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
    }

    private static func resolveURL(for fileName: String, withExtension fileExtension: String) -> URL? {
        let bundle = Bundle.main

        if let directURL = bundle.url(forResource: fileName, withExtension: fileExtension) {
            return directURL
        }

        return bundle.url(forResource: fileName,
                          withExtension: fileExtension,
                          subdirectory: "Sounds")
    }

    private func configureAudioSession() {
#if os(iOS)
        // Mix with other audio so ambient sounds can play alongside other media.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Fallback to default session behaviour if configuration fails.
        }
#endif
    }

    private func effectiveVolume(for sound: AmbientSound) -> Float {
        guard !isMuted else { return 0 }
        return sliderVolumes[sound.id] ?? 1.0
    }

    private func refreshActivePlayerVolumes() {
        for (id, player) in players {
            let volume = isMuted ? 0 : (sliderVolumes[id] ?? 1.0)
            player.setVolume(volume, fadeDuration: 0)
        }
    }
}
