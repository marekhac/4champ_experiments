//
//  CarPlayModels.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

enum CarPlayRadioChannel {
    case new
    case all
    case collection
    case custom

    var title: String {
        switch self {
        case .new:        return "New"
        case .all:        return "All"
        case .collection: return "Collection"
        case .custom:     return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .new:        return "Latest modules from AMP"
        case .all:        return "Random modules from AMP"
        case .collection: return "Random modules from your collection"
        case .custom:     return "Play a playlist"
        }
    }
}

struct CarPlayRadioState {
    var isActive = false
    var channel: CarPlayRadioChannel = .new
    var lastPlayed = 0
}
