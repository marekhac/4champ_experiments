//
//  CarPlayController+Radio.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay
import CoreData
import Foundation

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

        radioState.isActive = true
        radioState.channel = channel

        if channel == .new {
            radioState.lastPlayed = settings.collectionSize
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

        radioState.isActive = true
        radioState.channel = .collection

        modulePlayer.playQueue = queue
        modulePlayer.play(at: 0)
    }

    func pushPlaylistPicker() {
        let playlists = fetchAllPlaylists()
        let items = playlists.isEmpty
            ? [CPListItem(text: "No playlists available", detailText: nil)]
            : playlists.map { makePlaylistItem(for: $0) }
        let template = CPListTemplate(title: "Custom", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    private func makePlaylistItem(for playlist: Playlist) -> CPListItem {
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

    func startCustomRadio(playlist: Playlist) {
        var queue: [MMD] = []
        playlist.modules?.forEach {
            if let modInfo = $0 as? ModuleInfo { queue.append(MMD(cdi: modInfo)) }
        }
        guard !queue.isEmpty else { return }
        stopRadio()
        modulePlayer.stop()
        modulePlayer.cleanup()

        radioState.isActive = true
        radioState.channel = .custom

        modulePlayer.playQueue = queue
        modulePlayer.play(at: 0)
    }

    // MARK: - Radio buffer management

    // Fetches one module from AMP server and appends it to the buffer (New / All channels)
    func fillRadioBuffer() {
        guard radioState.isActive else { return }
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
        switch radioState.channel {
        case .new:
            guard radioState.lastPlayed > 0 else { return nil }
            defer { radioState.lastPlayed -= 1 }
            return radioState.lastPlayed

        case .all:
            return Int.random(in: 1...settings.collectionSize)

        default:
            return nil
        }
    }

    func stopRadio() {
        radioState = CarPlayRadioState()

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
        return (try? moduleStorage.managedObjectContext.fetch(request)) ?? []
    }
}
