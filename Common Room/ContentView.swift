//
//  ContentView.swift
//  Common Room
//
//  Created by duck on 16/09/2025.
//

import Combine
import SwiftUI

/// Entry point that renders the list of ambient sound cards.
struct ContentView: View {
    @AppStorage("soundVolumes") private var storedVolumesData: Data = Data()
    @AppStorage("soundIntervals") private var storedIntervalsData: Data = Data()
    @AppStorage("globalMute") private var storedGlobalMute: Bool = false

    private let sounds: [AmbientSound]
    @StateObject private var playbackManager: SoundPlaybackManager

    private let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.13, blue: 0.23).opacity(0.95),
            Color(red: 0.18, green: 0.24, blue: 0.40).opacity(0.85),
            Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    init() {
        let thunderVariants = (1...11).map { index in
            String(format: "thunder%02d", index)
        }

        let thunderInterval = AmbientSound.IntervalConfiguration(
            defaultInterval: 30,
            range: 10...60
        )

        let configuredSounds: [AmbientSound] = [
            AmbientSound(
                name: "Rain",
                iconName: "cloud.rain.fill",
                playback: .looping(file: "rain")
            ),
            AmbientSound(
                name: "Fireplace",
                iconName: "flame.fill",
                playback: .looping(file: "fireplace")
            ),
            AmbientSound(
                name: "Cafe",
                iconName: "cup.and.saucer.fill",
                playback: .looping(file: "cafe")
            ),
            AmbientSound(
                name: "Thunder",
                iconName: "cloud.bolt.rain.fill",
                playback: .intervalRandom(files: thunderVariants, interval: thunderInterval)
            )
        ]

        self.sounds = configuredSounds

        let defaults = UserDefaults.standard
        let storedVolumeData = defaults.data(forKey: "soundVolumes") ?? Data()
        let storedIntervalData = defaults.data(forKey: "soundIntervals") ?? Data()
        let initialVolumes = SoundSettingsCodec.decodeVolumes(from: storedVolumeData)
        let initialIntervals = SoundSettingsCodec.decodeIntervals(from: storedIntervalData)
        let initialMute = defaults.object(forKey: "globalMute") as? Bool ?? false

        let manager = SoundPlaybackManager(
            sounds: configuredSounds,
            initialVolumes: initialVolumes,
            initialIntervals: initialIntervals,
            initialMute: initialMute
        )

        _playbackManager = StateObject(wrappedValue: manager)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                List(sounds) { sound in
                    SoundRow(
                        sound: sound,
                        isPlaying: playbackManager.isPlaying(sound),
                        volume: Binding(
                            get: { playbackManager.volume(for: sound) },
                            set: { playbackManager.setVolume($0, for: sound) }
                        ),
                        intervalControls: intervalControls(for: sound),
                        onToggle: { playbackManager.toggle(sound) }
                    )
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .listRowSeparator(.hidden)
                .padding(.top, 12)
            }
            .navigationTitle("Ambient Sounds")
#if os(macOS)
            .listStyle(.plain)
#else
            .listStyle(.insetGrouped)
#endif
        }
        .frame(minWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            MuteButton(isMuted: playbackManager.isMuted) {
                playbackManager.toggleMute()
            }
            .padding(.leading, 20)
            .padding(.bottom, 20)
        }
        .onReceive(playbackManager.$sliderVolumes) { volumes in
            let data = SoundSettingsCodec.encode(volumes: volumes)
            if storedVolumesData != data {
                storedVolumesData = data
            }
        }
        .onReceive(playbackManager.$intervalDurations) { intervals in
            let data = SoundSettingsCodec.encode(intervals: intervals)
            if storedIntervalsData != data {
                storedIntervalsData = data
            }
        }
        .onReceive(playbackManager.$isMuted) { isMuted in
            if storedGlobalMute != isMuted {
                storedGlobalMute = isMuted
            }
        }
    }

    private func intervalControls(for sound: AmbientSound) -> SoundRow.IntervalControls? {
        guard let configuration = sound.intervalConfiguration else { return nil }

        let binding = Binding<Double>(
            get: { playbackManager.interval(for: sound) },
            set: { playbackManager.setInterval($0, for: sound) }
        )

        let range = Double(configuration.range.lowerBound)...Double(configuration.range.upperBound)
        return SoundRow.IntervalControls(value: binding, range: range)
    }
}

/// Individual card showing metadata, controls and sliders for a sound.
private struct SoundRow: View {
    struct IntervalControls {
        let value: Binding<Double>
        let range: ClosedRange<Double>
    }

    let sound: AmbientSound
    let isPlaying: Bool
    @Binding var volume: Float
    let intervalControls: IntervalControls?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sliders
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 14)
        )
    }

    private var header: some View {
        HStack(spacing: 18) {
            iconPlate

            VStack(alignment: .leading, spacing: 6) {
                Text(sound.name)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(isPlaying ? "Now playing" : "Tap to play")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 16)

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .buttonStyle(GlassButtonStyle())
            .contentShape(Rectangle())
        }
    }

    private var iconPlate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 8)

            Image(systemName: sound.iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 58, height: 58)
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float($0) }
                ),
                in: 0...1
            )
            .tint(.white)
            .controlSize(.large)

            HStack {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let intervalControls {
                Slider(value: intervalControls.value,
                       in: intervalControls.range,
                       step: 1)
                    .tint(.white)
                    .controlSize(.large)

                HStack {
                    Text("Interval")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Int(intervalControls.value.wrappedValue))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

/// Floating control to quickly silence or resume all playback.
private struct MuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(isMuted ? "Muted" : "Mute")
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

private enum SoundSettingsCodec {
    static func decodeVolumes(from data: Data) -> [String: Float] {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode([String: Float].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func encode(volumes: [String: Float]) -> Data {
        (try? JSONEncoder().encode(volumes)) ?? Data()
    }

    static func decodeIntervals(from data: Data) -> [String: TimeInterval] {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func encode(intervals: [String: TimeInterval]) -> Data {
        (try? JSONEncoder().encode(intervals)) ?? Data()
    }
}

/// Frosted, press-responsive style shared across the control buttons.
private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
