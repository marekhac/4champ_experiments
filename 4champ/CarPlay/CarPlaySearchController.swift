//
//  CarPlayController.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Aleksi Sitomaniemi. All rights reserved.
//

import CarPlay
import CoreData
import Foundation
import MediaPlayer

enum CarPlayRadioChannel { case new, all, collection, custom }

class CarPlayController: NSObject {

    private weak var interfaceController: CPInterfaceController?
    private var fetcher: ModuleFetcher?
    private var lastPlayedModules: [MMD] = []
    private var nowPlayingTemplate: CPListTemplate?
    private var isRadioActive = false
    private var radioChannel: CarPlayRadioChannel = .new
    private var radioLastPlayed = 0
    private var radioFetchers: [ModuleFetcher] = []

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
        modulePlayer.addPlayerObserver(self)
        setupRemoteCommands()
    }

    deinit {
        teardownRemoteCommands()
        modulePlayer.removePlayerObserver(self)
        radioFetchers.forEach { $0.cancel() }
    }

    // MARK: - Root template

    func makeRootTemplate() -> CPListTemplate {
        let lastPlayedItem = CPListItem(text: "Last played",
                                        detailText: "Recently played modules",
                                        image: nil,
                                        showsDisclosureIndicator: true)
        lastPlayedItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.pushLastPlayedTemplate() }
            done()
        }
        let radioItem = CPListItem(text: "Radio",
                                   detailText: "Stream modules from AMP",
                                   image: nil,
                                   showsDisclosureIndicator: true)
        radioItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.pushRadioTemplate() }
            done()
        }
        return CPListTemplate(title: "4champ", sections: [CPListSection(items: [lastPlayedItem, radioItem])])
    }

    // MARK: - Remote command centre

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            modulePlayer.resume()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            modulePlayer.pause()
            return .success
        }

        center.stopCommand.isEnabled = true
        center.stopCommand.addTarget { _ in
            modulePlayer.stop()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            modulePlayer.playNext()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            modulePlayer.playPrev()
            return .success
        }
    }

    private func teardownRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
    }

    // MARK: - Custom Now Playing template

    private func makeNowPlayingSections(module: MMD, isPlaying: Bool) -> [CPListSection] {
        // Info row: floppy disk icon + module name + composer
        let starIcon = controlIcon(named: module.favorite ? "favestar-yellow" : "favestar-grey")
        let yellowIcon = controlIcon(named: "favestar-yellow")
        let greyIcon = controlIcon(named: "favestar-grey")
        let composer = module.composer?.trimmingCharacters(in: .whitespaces)
        let title = module.name.count > 25 ? String(module.name.prefix(25)) + "…" : module.name
        let infoItem = CPListItem(text: title,
                                  detailText: (composer?.isEmpty == false) ? composer : nil,
                                  image: moduleIcon(for: module),
                                  accessoryImage: starIcon,
                                  accessoryType: .none)
        infoItem.handler = { [weak infoItem] _, done in
            DispatchQueue.main.async {
                guard let infoItem else { done(); return }
                if let updated = moduleStorage.toggleFavorite(module: module) {
                    infoItem.setAccessoryImage(updated.favorite ? yellowIcon : greyIcon)
                }
                done()
            }
        }

        // Playback control rows
        let toggleItem = CPListItem(text: isPlaying ? "Pause" : "Play", detailText: nil,
                                    image: controlIcon(named: isPlaying ? "pause-small" : "play-small"))
        toggleItem.handler = { _, done in
            if modulePlayer.status == .playing { modulePlayer.pause() } else { modulePlayer.resume() }
            done()
        }

        let prevItem = CPListItem(text: "Previous", detailText: nil, image: controlIcon(named: "prev-small"))
        prevItem.handler = { _, done in
            modulePlayer.playPrev()
            done()
        }

        let nextItem = CPListItem(text: "Next", detailText: nil, image: controlIcon(named: "next-small"))
        nextItem.handler = { _, done in
            modulePlayer.playNext()
            done()
        }

        return [
            CPListSection(items: [infoItem]),
            CPListSection(items: [toggleItem, prevItem, nextItem])
        ]
    }

    private func showOrUpdateNowPlaying(module: MMD, isPlaying: Bool) {
        let sections = makeNowPlayingSections(module: module, isPlaying: isPlaying)
        if let existing = nowPlayingTemplate,
           interfaceController?.topTemplate === existing {
            existing.updateSections(sections)
        } else {
            let template = CPListTemplate(title: "Now Playing", sections: sections)
            nowPlayingTemplate = template
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    // MARK: - MPNowPlayingInfoCenter (lock screen / AirPlay)

    private func setNowPlayingInfo(for module: MMD, playbackRate: Double) {
        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300)) { _ in
            UIImage(named: "albumart") ?? UIImage()
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: module.name,
            MPMediaItemPropertyArtist: module.composer ?? "",
            MPMediaItemPropertyArtwork: artwork,
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: playbackRate),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: Double(modulePlayer.renderer.currentPosition())),
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: Double(modulePlayer.renderer.moduleLength()))
        ]
    }

    private func updatePlaybackRate(_ rate: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Image helpers

    private func controlIcon(named name: String) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func moduleIcon(for module: MMD) -> UIImage? {
        guard let base = UIImage(named: "modicon") else { return nil }
        let size = base.size
        return UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            guard let format = module.type, !format.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkText
            ]
            let text = format.uppercased() as NSString
            let textSize = text.size(withAttributes: attrs)
            let point = CGPoint(x: (size.width - textSize.width) / 2,
                                y: size.height - textSize.height - 8)
            text.draw(at: point, withAttributes: attrs)
        }
    }

    // MARK: - Navigation helpers

    private func pushLastPlayedTemplate() {
        let items: [CPListItem]
        if lastPlayedModules.isEmpty {
            items = [CPListItem(text: "No modules played yet", detailText: nil)]
        } else {
            items = lastPlayedModules.map { mmd in
                let parts = [mmd.composer, mmd.type].compactMap { $0 }.filter { !$0.isEmpty }
                let detail = parts.joined(separator: " • ")
                let item = CPListItem(text: mmd.name, detailText: detail.isEmpty ? nil : detail)
                item.handler = { [weak self] _, done in
                    DispatchQueue.main.async { self?.playOrFetch(mmd: mmd) }
                    done()
                }
                return item
            }
        }
        let template = CPListTemplate(title: "Last played", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func playOrFetch(mmd: MMD) {
        if mmd.fileExists() {
            modulePlayer.play(mmd: mmd)
        } else if let id = mmd.id {
            fetcher?.cancel()
            fetcher = ModuleFetcher(delegate: self)
            fetcher?.fetchModule(ampId: id)
        }
    }

    // MARK: - Radio

    private func pushRadioTemplate() {
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
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func startNewRadio() {
        stopRadio()
        isRadioActive = true
        radioChannel = .new
        radioLastPlayed = settings.collectionSize
        modulePlayer.stop()
        modulePlayer.cleanup()
        fillRadioBuffer()
    }

    private func startAllRadio() {
        stopRadio()
        isRadioActive = true
        radioChannel = .all
        modulePlayer.stop()
        modulePlayer.cleanup()
        fillRadioBuffer()
    }

    private func startCollectionRadio() {
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

    private func pushPlaylistPicker() {
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
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func startCustomRadio(playlist: Playlist) {
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

    // Fetches all user playlists (excluding internal radioList)
    private func fetchAllPlaylists() -> [Playlist] {
        let request = Playlist.fetchRequest()
        request.predicate = NSPredicate(format: "plId != 'radioList'")
        request.sortDescriptors = [NSSortDescriptor(key: "plName", ascending: true)]
        let frc = moduleStorage.createFRC(fetchRequest: request, entityName: "Playlist")
        try? frc.performFetch()
        return frc.fetchedObjects ?? []
    }

    // Fetches one module from AMP server and adds it to the radio buffer (New / All channels)
    private func fillRadioBuffer() {
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

    private func stopRadio() {
        isRadioActive = false
        radioLastPlayed = 0
        radioFetchers.forEach { $0.cancel() }
        radioFetchers.removeAll()
    }

    // Removes the oldest AMP-fetched module from the buffer and deletes its temp file
    private func removeRadioBufferHead() {
        guard !modulePlayer.playQueue.isEmpty else { return }
        let head = modulePlayer.playQueue.removeFirst()
        guard let headId = head.id, moduleStorage.getModuleById(headId) == nil else { return }
        if let url = head.localPath {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - ModuleFetcherDelegate

extension CarPlayController: ModuleFetcherDelegate {

    func fetcherStateChanged(_ fetcher: ModuleFetcher, state: FetcherState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let isRadioFetcher = self.radioFetchers.contains { $0 === fetcher }
            switch state {
            case .done(let mmd):
                if isRadioFetcher {
                    self.radioFetchers.removeAll { $0 === fetcher }
                    guard self.isRadioActive else { return }
                    modulePlayer.playQueue.append(mmd)
                    if modulePlayer.playQueue.first == mmd {
                        modulePlayer.play(at: 0)
                    }
                    self.fillRadioBuffer()
                } else {
                    modulePlayer.play(mmd: mmd)
                }
            case .failed:
                if isRadioFetcher {
                    self.radioFetchers.removeAll { $0 === fetcher }
                    if self.isRadioActive { self.fillRadioBuffer() }
                } else {
                    let action = CPAlertAction(title: "OK", style: .default, handler: { _ in })
                    let alert = CPAlertTemplate(titleVariants: ["Download Failed"], actions: [action])
                    self.interfaceController?.presentTemplate(alert, animated: true, completion: nil)
                }
            default:
                break
            }
        }
    }
}

// MARK: - ModulePlayerObserver

extension CarPlayController: ModulePlayerObserver {

    func statusChanged(status: PlayerStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch status {
            case .playing:
                guard let module = modulePlayer.currentModule else { return }
                self.setNowPlayingInfo(for: module, playbackRate: 1.0)
                self.showOrUpdateNowPlaying(module: module, isPlaying: true)
            case .paused:
                self.updatePlaybackRate(0.0)
                if let module = modulePlayer.currentModule {
                    self.nowPlayingTemplate?.updateSections(
                        self.makeNowPlayingSections(module: module, isPlaying: false)
                    )
                }
            default:
                break
            }
        }
    }

    func moduleChanged(module: MMD, previous: MMD?) {
        lastPlayedModules.removeAll { $0.id == module.id }
        lastPlayedModules.insert(module, at: 0)
        if lastPlayedModules.count > 20 {
            lastPlayedModules = Array(lastPlayedModules.prefix(20))
        }
        if isRadioActive {
            switch radioChannel {
            case .new, .all:
                if let index = modulePlayer.playQueue.firstIndex(of: module), index > 0 {
                    removeRadioBufferHead()
                }
                fillRadioBuffer()
            case .collection:
                // Remove consumed head (no file deletion — these are saved modules)
                if let index = modulePlayer.playQueue.firstIndex(of: module), index > 0 {
                    modulePlayer.playQueue.removeFirst()
                }
                // Replenish with another random local module
                if let next = moduleStorage.getRandomModule() {
                    modulePlayer.playQueue.append(next)
                }
            case .custom:
                break // Queue is fully pre-loaded; playNext() loops naturally
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setNowPlayingInfo(for: module, playbackRate: 1.0)
            self.nowPlayingTemplate?.updateSections(
                self.makeNowPlayingSections(module: module, isPlaying: modulePlayer.status == .playing)
            )
        }
    }

    func errorOccurred(error: PlayerError) {}
    func queueChanged(changeType: QueueChange) {}
}
