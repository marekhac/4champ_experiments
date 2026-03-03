//
//  CarPlayController.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Aleksi Sitomaniemi. All rights reserved.
//

import CarPlay
import Foundation
import MediaPlayer

class CarPlayController: NSObject {

    private weak var interfaceController: CPInterfaceController?
    private var fetcher: ModuleFetcher?
    private var lastPlayedModules: [MMD] = []
    private var nowPlayingTemplate: CPListTemplate?
    private var isRadioActive = false
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
        let allItem = CPListItem(text: "All", detailText: "Random modules (coming soon)")
        allItem.isEnabled = false
        let collectionItem = CPListItem(text: "Collection", detailText: "Saved modules (coming soon)")
        collectionItem.isEnabled = false
        let customItem = CPListItem(text: "Custom", detailText: "Custom selection (coming soon)")
        customItem.isEnabled = false
        let template = CPListTemplate(
            title: "Radio",
            sections: [CPListSection(items: [newItem, allItem, collectionItem, customItem])]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func startNewRadio() {
        stopRadio()
        isRadioActive = true
        radioLastPlayed = settings.collectionSize
        modulePlayer.stop()
        modulePlayer.cleanup()
        fillRadioBuffer()
    }

    private func fillRadioBuffer() {
        guard isRadioActive else { return }
        guard Constants.radioBufferLen > modulePlayer.playQueue.count else { return }
        guard radioLastPlayed > 0 else { return }
        let id = radioLastPlayed
        radioLastPlayed -= 1
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
            if let index = modulePlayer.playQueue.firstIndex(of: module), index > 0 {
                removeRadioBufferHead()
            }
            fillRadioBuffer()
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
