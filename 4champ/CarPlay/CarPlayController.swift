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

    weak var interfaceController: CPInterfaceController?
    var fetcher: ModuleFetcher?
    var lastPlayedModules: [MMD] = []
    var nowPlayingTemplate: CPListTemplate?

    // Radio state — shared with CarPlayController+Radio.swift
    var isRadioActive = false
    var radioChannel: CarPlayRadioChannel = .new
    var radioLastPlayed = 0
    var radioFetchers: [ModuleFetcher] = []

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
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
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
}
