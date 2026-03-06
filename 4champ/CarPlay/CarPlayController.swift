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
import UIKit

class CarPlayController: NSObject {

    // MARK: - Dependencies

    weak var interfaceController: CPInterfaceController?
    var fetcher: ModuleFetcher?

    // MARK: - Templates

    var nowPlayingTemplate: CPListTemplate?
    private var collectionTemplate: CPListTemplate?

    // MARK: - Radio State

    var isRadioActive = false
    var radioChannel: CarPlayRadioChannel = .new
    var radioLastPlayed = 0
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

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        registerCommand(center.playCommand) { modulePlayer.resume() }
        registerCommand(center.pauseCommand) { modulePlayer.pause() }
        registerCommand(center.stopCommand) { modulePlayer.stop() }
        registerCommand(center.nextTrackCommand) { modulePlayer.playNext() }
        registerCommand(center.previousTrackCommand) { modulePlayer.playPrev() }
    }

    private func registerCommand(_ command: MPRemoteCommand, action: @escaping () -> Void) {
        command.isEnabled = true
        command.addTarget { _ in
            action()
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

    private func pushFavouritesTemplate() {
        let template = CPListTemplate(title: "Collection", sections: makeCollectionSections())
        collectionTemplate = template
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    private func makeCollectionSections() -> [CPListSection] {
        let modules = fetchCollection()
        guard !modules.isEmpty else {
            return [CPListSection(items: [CPListItem(text: "No modules in collection", detailText: nil)])]
        }
        let items = modules.enumerated().map { index, mmd in
            let starIcon = controlIcon(named: mmd.favorite ? "favestar-yellow" : "favestar-grey")?.withRenderingMode(.alwaysOriginal)
            let item = CPListItem(text: mmd.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  detailText: mmd.composer,
                                  image: moduleIcon(for: mmd),
                                  accessoryImage: starIcon,
                                  accessoryType: .none)
            item.handler = { [weak self] _, done in
                DispatchQueue.main.async { self?.playFavourites(modules, startingAt: index) }
                done()
            }
            return item
        }
        return [CPListSection(items: items)]
    }

    private func fetchCollection() -> [MMD] {
        let request: NSFetchRequest<ModuleInfo> = NSFetchRequest(entityName: "ModuleInfo")
        do {
            return try moduleStorage.managedObjectContext.fetch(request)
                .filter { $0.radioOnly == nil || $0.radioOnly?.intValue == 0 }
                .map(MMD.init)
                .sorted { lhs, rhs in
                    let a = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let b = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
        } catch {
            log.error("CarPlay: fetchCollection failed: \(error)")
            return []
        }
    }

    private func playFavourites(_ modules: [MMD], startingAt index: Int) {
        stopRadio()
        modulePlayer.playQueue = modules
        modulePlayer.play(at: index)
    }
}

// MARK: - ModuleStorageObserver

extension CarPlayController: ModuleStorageObserver {
    func metadataChange(_ mmd: MMD) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let template = self.collectionTemplate else { return }
            template.updateSections(self.makeCollectionSections())
        }
    }

    func playlistChange() {}
}
