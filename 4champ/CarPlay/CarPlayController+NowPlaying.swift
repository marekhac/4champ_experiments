//
//  CarPlayController+NowPlaying.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Aleksi Sitomaniemi. All rights reserved.
//

import CarPlay
import MediaPlayer
import UIKit

// MARK: - Now Playing template

extension CarPlayController {
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
        lazy var artwork: MPMediaItemArtwork = {
            let image = UIImage(named: "albumart") ?? UIImage()
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }()

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
        changes.forEach { info[$0.key] = $0.value }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackRate(_ rate: Double) {
        updateNowPlayingInfo([
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ])
    }

    // MARK: - Image helpers

    func controlIcon(named name: String) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func moduleIcon(for module: MMD) -> UIImage? {
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
}

// MARK: - ModuleFetcherDelegate

extension CarPlayController: ModuleFetcherDelegate {

// TODO:
//    private func handleRadioFetcherDone(_ fetcher: ModuleFetcher, mmd: MMD)
//    private func handleManualFetcherDone(_ fetcher: ModuleFetcher, mmd: MMD)

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
                } else if self.fetcher === fetcher {
                    // Only act if this is still the active manual fetcher
                    self.fetcher = nil
                    modulePlayer.play(mmd: mmd)
                }
                // else: stale fetcher from a previous radio or play session — discard
            case .failed:
                if isRadioFetcher {
                    self.radioFetchers.removeAll { $0 === fetcher }
                    if self.isRadioActive { self.fillRadioBuffer() }
                } else if self.fetcher === fetcher {
                    // Only show error for the active manual fetcher
                    self.fetcher = nil
                    let action = CPAlertAction(title: "OK", style: .default, handler: { _ in })
                    let alert = CPAlertTemplate(titleVariants: ["Download Failed"], actions: [action])
                    self.interfaceController?.presentTemplate(alert, animated: true) { _, _ in }
                }
                // else: stale fetcher — discard silently
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
        if isRadioActive {
            switch radioChannel {
            case .new, .all:
                if let index = modulePlayer.playQueue.firstIndex(of: module), index > 0 {
                    removeRadioBufferHead()
                }
                fillRadioBuffer()
            case .collection:
                if let index = modulePlayer.playQueue.firstIndex(of: module), index > 0 {
                    modulePlayer.playQueue.removeFirst()
                }
                if let next = moduleStorage.getRandomModule() {
                    modulePlayer.playQueue.append(next)
                }
            case .custom:
                break
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
