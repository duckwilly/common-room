//
//  AmbientSound.swift
//  Common Room
//
//  Created by duck on 16/09/2025.
//

import Foundation

/// Lightweight description for an ambient track the UI can present.
struct AmbientSound: Identifiable, Hashable {
    enum PlaybackMode {
        case looping(file: String)
        case intervalRandom(files: [String], interval: IntervalConfiguration)
    }

    struct IntervalConfiguration {
        let defaultInterval: TimeInterval
        let range: ClosedRange<TimeInterval>
    }

    let id: String
    let name: String
    let iconName: String
    let fileExtension: String
    let playback: PlaybackMode

    init(name: String,
         iconName: String,
         fileExtension: String = "mp3",
         playback: PlaybackMode) {
        self.id = name
        self.name = name
        self.iconName = iconName
        self.fileExtension = fileExtension
        self.playback = playback
    }

    var availableFiles: [String] {
        switch playback {
        case let .looping(file):
            return [file]
        case let .intervalRandom(files, _):
            return files
        }
    }

    var intervalConfiguration: IntervalConfiguration? {
        if case let .intervalRandom(_, interval) = playback {
            return interval
        }
        return nil
    }
}

extension AmbientSound {
    static func == (lhs: AmbientSound, rhs: AmbientSound) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

