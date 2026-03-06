//
//  CarPlayController+Radio.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Aleksi Sitomaniemi. All rights reserved.
//

import CarPlay
import CoreData
import Foundation

enum CarPlayRadioChannel {
    case new
    case all
    case collection
    case custom

    var title: String {
        switch self {
        case .new: return "New"
        case .all: return "All"
        case .collection: return "Collection"
        case .custom: return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .new: return "Latest modules from AMP"
        case .all: return "Random modules from AMP"
        case .collection: return "Random modules from your collection"
        case .custom: return "Play a playlist"
        }
    }
}

extension CarPlayController {

    // MARK: - Channel selection

    func pushRadioTemplate() {
        let channels: [(CarPlayRadioChannel, () -> Void)] = [
            (.new, startNewRadio),
            (.all, startAllRadio),
            (.collection, startCollectionRadio),
            (.custom, pushPlaylistPicker)
        ]

        let items = channels.map { channel, action in
            makeRadioItem(for: channel, action: action)
        }

        let template = CPListTemplate(
            title: "Radio",
            sections: [CPListSection(items: items)]
        )

        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    private func makeRadioItem(for channel: CarPlayRadioChannel, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(
            text: channel.title,
            detailText: channel.subtitle,
            image: nil,
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )

        item.handler = { _, completion in
            action()
            completion()
        }

        return item
    }

    // MARK: - Channel start

    private func startAMPChannel(_ channel: CarPlayRadioChannel) {
        stopRadio()

        isRadioActive = true
        radioChannel = channel

        if channel == .new {
            radioLastPlayed = settings.collectionSize
        }

        modulePlayer.stop()
        modulePlayer.cleanup()

        for _ in 0..<Constants.radioBufferLen { fillRadioBuffer() }
    }

    func startNewRadio() {
        startAMPChannel(.new)
    }

    func startAllRadio() {
        startAMPChannel(.all)
    }

    func startCollectionRadio() {
        stopRadio()

        modulePlayer.stop()
        modulePlayer.cleanup()

        let queue = (0..<Constants.radioBufferLen)
            .compactMap { _ in moduleStorage.getRandomModule() }

        guard !queue.isEmpty else { return }

        isRadioActive = true
        radioChannel = .collection

        modulePlayer.playQueue = queue
        modulePlayer.play(at: 0)
    }

    func pushPlaylistPicker() {
        let playlists = fetchAllPlaylists()
        let items: [CPListItem]
        if playlists.isEmpty {
            items = [CPListItem(text: "No playlists available", detailText: nil)]
        } else {
            items = playlists.map { playlist in
                let count = playlist.modules?.count ?? 0
                let item = CPListItem(text: playlist.plName ?? "Unnamed",
                                      detailText: "\(count) module\(count == 1 ? "" : "s")",
                                      image: nil,
                                      accessoryImage: nil,
                                      accessoryType: .disclosureIndicator)
                item.handler = { [weak self] _, done in
                    DispatchQueue.main.async { self?.startCustomRadio(playlist: playlist) }
                    done()
                }
                return item
            }
        }
        let template = CPListTemplate(title: "Custom", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    func startCustomRadio(playlist: Playlist) {
        var queue: [MMD] = []
        playlist.modules?.forEach {
            if let modInfo = $0 as? ModuleInfo { queue.append(MMD(cdi: modInfo)) }
        }
        guard !queue.isEmpty else { return }
        stopRadio()
        modulePlayer.stop()
        modulePlayer.cleanup()

        isRadioActive = true
        radioChannel = .custom

        modulePlayer.playQueue = queue
        modulePlayer.play(at: 0)
    }

    // MARK: - Buffer management

    // Fetches one module from AMP server and appends it to the buffer (New / All channels)
    func fillRadioBuffer() {
        guard isRadioActive else { return }
        // Count only modules ahead of the current one so history is preserved for playPrev()
        let aheadCount: Int
        if let current = modulePlayer.currentModule,
           let idx = modulePlayer.playQueue.firstIndex(of: current) {
            aheadCount = modulePlayer.playQueue.count - idx - 1
        } else {
            aheadCount = modulePlayer.playQueue.count
        }
        guard aheadCount + radioFetchers.count < Constants.radioBufferLen else { return }
        guard let id = nextAMPId() else { return }

        let fetcher = ModuleFetcher(delegate: self)
        radioFetchers.append(fetcher)
        fetcher.fetchModule(ampId: id)
    }

    private func nextAMPId() -> Int? {
        switch radioChannel {
        case .new:
            guard radioLastPlayed > 0 else { return nil }
            defer { radioLastPlayed -= 1 }
            return radioLastPlayed

        case .all:
            return Int.random(in: 1...settings.collectionSize)

        default:
            return nil
        }
    }

    func stopRadio() {
        isRadioActive = false
        radioLastPlayed = 0

        fetcher?.cancel()
        fetcher = nil

        radioFetchers.forEach { $0.cancel() }
        radioFetchers.removeAll(keepingCapacity: false)
    }

    // MARK: - Helpers

    private func fetchAllPlaylists() -> [Playlist] {
        let request = Playlist.fetchRequest()
        request.predicate = NSPredicate(format: "plId != 'radioList'")
        request.sortDescriptors = [NSSortDescriptor(key: "plName", ascending: true)]
        let frc = moduleStorage.createFRC(fetchRequest: request, entityName: "Playlist")
        try? frc.performFetch()
        return frc.fetchedObjects ?? []
    }
}
