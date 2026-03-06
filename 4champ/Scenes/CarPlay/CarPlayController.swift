//
//  CarPlayController.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay
import Foundation
import MediaPlayer
import UIKit

class CarPlayController: NSObject {

    // MARK: - Dependencies

    weak var interfaceController: CPInterfaceController?
    var fetcher: ModuleFetcher?

    // MARK: - Templates

    var nowPlayingTemplate: CPListTemplate?
    var collectionTemplate: CPListTemplate?

    // MARK: - Radio State

    var radioState = CarPlayRadioState()
    var radioFetchers: [ModuleFetcher] = []

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
        setup()
    }

    private func setup() {
        modulePlayer.addPlayerObserver(self)
        moduleStorage.addStorageObserver(self)
        setupRemoteCommands()
    }

    deinit {
        teardownRemoteCommands()
        modulePlayer.removePlayerObserver(self)
        moduleStorage.removeStorageObserver(self)
        fetcher?.cancel()
        radioFetchers.forEach { $0.cancel() }
    }

    // MARK: - Root template

    func makeRootTemplate() -> CPListTemplate {
        let favouritesItem = menuItem(text: "Collection",
                                      detail: "Your saved modules",
                                      imageName: "localMods") { [weak self] in
            self?.pushFavouritesTemplate()
        }
        let radioItem = menuItem(text: "Radio",
                                 detail: "Stream modules from AMP",
                                 imageName: "radio") { [weak self] in
            self?.pushRadioTemplate()
        }
        return CPListTemplate(title: "4champ", sections: [CPListSection(items: [favouritesItem, radioItem])])
    }

    private func menuItem(text: String, detail: String, imageName: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: text,
                              detailText: detail,
                              image: UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate),
                              accessoryImage: nil,
                              accessoryType: .disclosureIndicator)
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    // MARK: - Remote command centre

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        registerCommand(center.playCommand) { modulePlayer.resume() }
        registerCommand(center.pauseCommand) { modulePlayer.pause() }
        registerCommand(center.stopCommand) { modulePlayer.stop() }
        registerCommand(center.nextTrackCommand) { modulePlayer.playNext() }
        registerCommand(center.previousTrackCommand) { modulePlayer.playPrev() }
    }

    func teardownRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
    }

    private func registerCommand(_ command: MPRemoteCommand, action: @escaping () -> Void) {
        command.isEnabled = true
        command.addTarget { _ in
            action()
            return .success
        }
    }

    // MARK: - Now Playing template

    func makeNowPlayingSections(module: MMD, isPlaying: Bool) -> [CPListSection] {
        let starIcon = controlIcon(named: module.favorite ? "favestar-yellow" : "favestar-grey")
        let yellowIcon = controlIcon(named: "favestar-yellow")
        let greyIcon = controlIcon(named: "favestar-grey")
        let composer = module.composer?.trimmingCharacters(in: .whitespaces)
        let title = truncated(module.name, limit: 25)
        let infoItem = CPListItem(text: title,
                                  detailText: (composer?.isEmpty == false) ? composer : nil,
                                  image: moduleIcon(for: module),
                                  accessoryImage: starIcon,
                                  accessoryType: .none)
        infoItem.handler = { [weak infoItem] _, completion in
            guard let infoItem else { completion(); return }
            if let updated = moduleStorage.toggleFavorite(module: module) {
                infoItem.setAccessoryImage(updated.favorite ? yellowIcon : greyIcon)
            }
            completion()
        }

        let toggleItem = controlItem(title: isPlaying ? "Pause" : "Play", iconName: isPlaying ? "pause-small" : "play-small") {
            modulePlayer.status == .playing ? modulePlayer.pause() : modulePlayer.resume()
        }
        let prevItem = controlItem(title: "Previous", iconName: "prev-small") {
            modulePlayer.playPrev()
        }
        let nextItem = controlItem(title: "Next", iconName: "next-small") {
            modulePlayer.playNext()
        }

        return [
            CPListSection(items: [infoItem]),
            CPListSection(items: [toggleItem, prevItem, nextItem])
        ]
    }

    private func controlItem(title: String, iconName: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil, image: controlIcon(named: iconName))
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return text.prefix(limit) + "…"
    }

    func showOrUpdateNowPlaying(module: MMD, isPlaying: Bool) {
        let sections = makeNowPlayingSections(module: module, isPlaying: isPlaying)
        let isVisible = interfaceController?.topTemplate === nowPlayingTemplate

        if isVisible, let existing = nowPlayingTemplate {
            existing.updateSections(sections)
        } else {
            let template = CPListTemplate(title: "Now Playing", sections: sections)
            nowPlayingTemplate = template
            push(template)
        }
    }

    func push(_ template: CPListTemplate) {
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    // MARK: - MPNowPlayingInfoCenter (lock screen / AirPlay)

    func setNowPlayingInfo(for module: MMD, playbackRate: Double) {
        let image = UIImage(named: "albumart") ?? UIImage()
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: module.name,
            MPMediaItemPropertyArtist: module.composer ?? "",
            MPMediaItemPropertyArtwork: artwork,
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: playbackRate),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: Double(modulePlayer.renderer.currentPosition())),
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: Double(modulePlayer.renderer.moduleLength()))
        ]
    }

    private func updateNowPlayingInfo(_ changes: [String: Any]) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info.merge(changes) { _, new in new }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackRate(_ rate: Double) {
        updateNowPlayingInfo([
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ])
    }

    // MARK: - Image helpers

    private static let formatLabelAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 10),
        .foregroundColor: UIColor.darkText
    ]

    func controlIcon(named name: String) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func moduleIcon(for module: MMD) -> UIImage? {
        guard let base = UIImage(named: "modicon") else { return nil }
        return UIGraphicsImageRenderer(size: base.size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            if let format = module.type, !format.isEmpty {
                drawFormatLabel(format, in: base.size)
            }
        }
    }

    // Must be called from within an active UIGraphicsImageRenderer context.
    private func drawFormatLabel(_ format: String, in size: CGSize) {
        let text = format.uppercased() as NSString
        let textSize = text.size(withAttributes: Self.formatLabelAttrs)
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: size.height - textSize.height - 8
        )
        text.draw(at: origin, withAttributes: Self.formatLabelAttrs)
    }
}

// MARK: - ModuleFetcherDelegate

extension CarPlayController: ModuleFetcherDelegate {

    private enum FetcherRole { case radio, manual, stale }

    private func role(of fetcher: ModuleFetcher) -> FetcherRole {
        if radioFetchers.contains(where: { $0 === fetcher }) { return .radio }
        if self.fetcher === fetcher { return .manual }
        return .stale
    }

    func fetcherStateChanged(_ fetcher: ModuleFetcher, state: FetcherState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.role(of: fetcher) {
            case .radio:   self.handleRadioFetch(fetcher: fetcher, state: state)
            case .manual:  self.handleManualFetch(fetcher: fetcher, state: state)
            case .stale:   break
            }
        }
    }

    private func handleRadioFetch(fetcher: ModuleFetcher, state: FetcherState) {
        switch state {
        case .done(let mmd):
            radioFetchers.removeAll { $0 === fetcher }
            guard radioState.isActive else { return }
            modulePlayer.playQueue.append(mmd)
            if modulePlayer.playQueue.first == mmd { modulePlayer.play(at: 0) }
            fillRadioBuffer()
        case .failed:
            radioFetchers.removeAll { $0 === fetcher }
            if radioState.isActive { fillRadioBuffer() }
        default:
            break
        }
    }

    private func handleManualFetch(fetcher: ModuleFetcher, state: FetcherState) {
        switch state {
        case .done(let mmd):
            self.fetcher = nil
            modulePlayer.play(mmd: mmd)
        case .failed:
            self.fetcher = nil
            showDownloadError()
        default:
            break
        }
    }

    private func showDownloadError() {
        let alert = CPAlertTemplate(
            titleVariants: ["Download Failed"],
            actions: [CPAlertAction(title: "OK", style: .default) { _ in }]
        )
        interfaceController?.presentTemplate(alert, animated: true) { _, _ in }
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.radioState.isActive {
                switch self.radioState.channel {
                case .new, .all:
                    // Keep played modules in queue so playPrev() can navigate back.
                    // fillRadioBuffer checks how many modules are ahead of the current one.
                    self.fillRadioBuffer()
                case .collection:
                    // Append a new random module to keep the stream going, but do NOT
                    // remove the head so prev/next navigation works across history.
                    if let next = moduleStorage.getRandomModule() {
                        modulePlayer.playQueue.append(next)
                    }
                case .custom:
                    break
                }
            }
            self.setNowPlayingInfo(for: module, playbackRate: 1.0)
            self.nowPlayingTemplate?.updateSections(
                self.makeNowPlayingSections(module: module, isPlaying: modulePlayer.status == .playing)
            )
        }
    }

    func errorOccurred(error: PlayerError) {}
    func queueChanged(changeType: QueueChange) {}
}
