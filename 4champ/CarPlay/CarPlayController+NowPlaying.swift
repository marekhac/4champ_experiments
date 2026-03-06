//
//  CarPlayController+NowPlaying.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay
import MediaPlayer
import UIKit

extension CarPlayController {

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
}
