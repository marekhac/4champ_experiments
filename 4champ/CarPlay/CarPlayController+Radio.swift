//
//  CarPlayController+Radio.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Aleksi Sitomaniemi. All rights reserved.
//

import CarPlay
import CoreData
import Foundation

enum CarPlayRadioChannel { case new, all, collection, custom }

extension CarPlayController {

    // MARK: - Channel selection

    func pushRadioTemplate() {
        let newItem = CPListItem(text: "New",
                                 detailText: "Latest modules from AMP",
                                 image: nil,
                                 showsDisclosureIndicator: true)
        newItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.startNewRadio() }
            done()
        }
        let allItem = CPListItem(text: "All",
                                 detailText: "Random modules from AMP",
                                 image: nil,
                                 showsDisclosureIndicator: true)
        allItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.startAllRadio() }
            done()
        }
        let collectionItem = CPListItem(text: "Collection",
                                        detailText: "Random modules from your collection",
                                        image: nil,
                                        showsDisclosureIndicator: true)
        collectionItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.startCollectionRadio() }
            done()
        }
        let customItem = CPListItem(text: "Custom",
                                    detailText: "Play a playlist",
                                    image: nil,
                                    showsDisclosureIndicator: true)
        customItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.pushPlaylistPicker() }
            done()
        }
        let template = CPListTemplate(
            title: "Radio",
            sections: [CPListSection(items: [newItem, allItem, collectionItem, customItem])]
        )
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    // MARK: - Channel start

    func startNewRadio() {
        stopRadio()
        isRadioActive = true
        radioChannel = .new
        radioLastPlayed = settings.collectionSize
        modulePlayer.stop()
        modulePlayer.cleanup()
        fillRadioBuffer()
    }

    func startAllRadio() {
        stopRadio()
        isRadioActive = true
        radioChannel = .all
        modulePlayer.stop()
        modulePlayer.cleanup()
        fillRadioBuffer()
    }

    func startCollectionRadio() {
        stopRadio()
        modulePlayer.stop()
        modulePlayer.cleanup()
        var queue: [MMD] = []
        for _ in 0..<Constants.radioBufferLen {
            guard let mmd = moduleStorage.getRandomModule() else { break }
            queue.append(mmd)
        }
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
                                      showsDisclosureIndicator: true)
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
        guard Constants.radioBufferLen > modulePlayer.playQueue.count else { return }
        let id: Int
        switch radioChannel {
        case .new:
            guard radioLastPlayed > 0 else { return }
            id = radioLastPlayed
            radioLastPlayed -= 1
        case .all:
            id = Int.random(in: 1...settings.collectionSize)
        default:
            return
        }
        let f = ModuleFetcher(delegate: self)
        radioFetchers.append(f)
        f.fetchModule(ampId: id)
    }

    func stopRadio() {
        isRadioActive = false
        radioLastPlayed = 0
        fetcher?.cancel()
        fetcher = nil
        radioFetchers.forEach { $0.cancel() }
        radioFetchers.removeAll()
    }

    // Removes the oldest AMP-fetched module from the buffer and deletes its temp file
    func removeRadioBufferHead() {
        guard !modulePlayer.playQueue.isEmpty else { return }
        let head = modulePlayer.playQueue.removeFirst()
        guard let headId = head.id, moduleStorage.getModuleById(headId) == nil else { return }
        if let url = head.localPath {
            try? FileManager.default.removeItem(at: url)
        }
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
