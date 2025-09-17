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
    private let availableSounds: [AmbientSound]
    @State private var showingSettings = false
    @State private var settingsTransitionProgress: Double = 0
    @StateObject private var playbackManager: SoundPlaybackManager

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

        self.availableSounds = configuredSounds

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
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(availableSounds) { sound in
                            soundRow(
                                for: sound,
                                transitionProgress: settingsTransitionProgress
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
                .background(.regularMaterial)
                .safeAreaPadding(.top, 72)
                .animation(.interactiveSpring(response: 0.55, dampingFraction: 0.82), value: settingsTransitionProgress)

                topBar
            }
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
        .background(.background)
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

    private func soundRow(for sound: AmbientSound, transitionProgress: Double) -> some View {
        let volumeBinding = Binding<Float>(
            get: { playbackManager.volume(for: sound) },
            set: { playbackManager.setVolume($0, for: sound) }
        )

        let isLast = sound.id == availableSounds.last?.id

        return SoundRow(
            sound: sound,
            isPlaying: playbackManager.isPlaying(sound),
            transitionProgress: transitionProgress,
            volume: volumeBinding,
            intervalControls: intervalControls(for: sound),
            onToggle: { playbackManager.toggle(sound) }
        )
        .padding(.bottom, isLast ? 80 : 0)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Common Room")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(action: toggleSettingsMode) {
                Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 20, weight: .medium))
                    .padding(12)
            }
            .buttonStyle(GlassButtonStyle())
            .accessibilityLabel(showingSettings ? "Exit settings" : "Open settings")
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.12), radius: 16, y: 6)
        )
    }

    private func toggleSettingsMode() {
        let targetProgress: Double

        if showingSettings {
            showingSettings = false
            targetProgress = 0
        } else {
            showingSettings = true
            targetProgress = 1
        }

        animateSettingsTransition(to: targetProgress)
    }

    private func animateSettingsTransition(to target: Double) {
        let animation = Animation.timingCurve(0.3, 0.8, 0.2, 1.0, duration: 0.65)
        withAnimation(animation) {
            settingsTransitionProgress = target
        }
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
    let transitionProgress: Double
    @Binding var volume: Float
    let intervalControls: IntervalControls?
    let onToggle: () -> Void
    @State private var sliderContentHeight: CGFloat = 0

    var body: some View {
        let metrics = SettingsLayoutMetrics(progress: transitionProgress)

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            header(metrics: metrics)
            sliders(metrics: metrics)
        }
        .padding(.vertical, metrics.verticalPadding)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.18), radius: 16, y: 8)
        )
        .scaleEffect(x: 1, y: metrics.cardScale, anchor: .center)
    }

    private func header(metrics: SettingsLayoutMetrics) -> some View {
        HStack(spacing: metrics.headerSpacing) {
            iconPlate(metrics: metrics)

            Text(sound.name)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 16)

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                    .padding(metrics.controlPadding)
            }
            .buttonStyle(GlassButtonStyle())
            .contentShape(Rectangle())
        }
    }

    private func iconPlate(metrics: SettingsLayoutMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.16), radius: 10, y: 6)

            Image(systemName: sound.iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: metrics.iconFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: metrics.iconSize, height: metrics.iconSize)
    }

    private func sliders(metrics: SettingsLayoutMetrics) -> some View {
        let visibility = CGFloat(metrics.sliderVisibility)

        return VStack(alignment: .leading, spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float($0) }
                ),
                in: 0...1
            )
            .tint(.accentColor)
            .controlSize(.large)

            HStack {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if let intervalControls {
                Slider(value: intervalControls.value,
                       in: intervalControls.range,
                       step: 1)
                    .tint(.accentColor)
                    .controlSize(.large)

                HStack {
                    Text("Interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(intervalControls.value.wrappedValue))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 6)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SliderHeightPreference.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SliderHeightPreference.self) { sliderContentHeight = $0 }
        .frame(height: max(0, sliderContentHeight * visibility), alignment: .top)
        .opacity(metrics.sliderOpacity)
        .scaleEffect(x: 1, y: metrics.sliderScale, anchor: .top)
        .offset(y: metrics.sliderOffset)
        .allowsHitTesting(metrics.sliderOpacity > 0.2)
    }

    private struct SettingsLayoutMetrics {
        let progress: Double

        private func phase(start: Double, end: Double) -> Double {
            guard end > start else { return progress >= end ? 1 : 0 }
            let normalized = (progress - start) / (end - start)
            return max(0, min(normalized, 1))
        }

        private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
            a + (b - a) * CGFloat(t)
        }

        private var sliderPhase: Double { phase(start: 0.0, end: 0.25) }
        private var scalePhase: Double { phase(start: 0.25, end: 0.55) }
        private var layoutPhase: Double { phase(start: 0.5, end: 1.0) }

        var sliderVisibility: Double { 1 - sliderPhase }
        var sliderOpacity: Double { sliderVisibility }
        var sliderScale: CGFloat { max(0.001, CGFloat(sliderVisibility)) }
        var sliderOffset: CGFloat { -12 * CGFloat(sliderPhase) }

        var cardScale: CGFloat { 1 - 0.065 * CGFloat(scalePhase) }
        var cardSpacing: CGFloat { lerp(18, 6, layoutPhase) }
        var verticalPadding: CGFloat { lerp(10, 6, layoutPhase) }
        var horizontalPadding: CGFloat { lerp(16, 12, layoutPhase) }
        var headerSpacing: CGFloat { lerp(18, 14, layoutPhase) }
        var iconSize: CGFloat { lerp(58, 52, layoutPhase) }
        var iconFontSize: CGFloat { lerp(26, 24, layoutPhase) }
        var controlPadding: CGFloat { lerp(14, 12, layoutPhase) }
    }
}

private struct SliderHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 18, weight: .semibold))
                Text(isMuted ? "Muted" : "Mute")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .foregroundStyle(.secondary)
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
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: Color(.sRGBLinear, white: 0, opacity: configuration.isPressed ? 0.1 : 0.18), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
