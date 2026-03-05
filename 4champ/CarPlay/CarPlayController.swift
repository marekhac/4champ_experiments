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
        radioFetchers.forEach { $0.cancel() }
    }

    // MARK: - Root template

    func makeRootTemplate() -> CPListTemplate {
        let favouritesItem = CPListItem(text: "Collection",
                                        detailText: "Your saved modules",
                                        image: UIImage(named: "localMods")?.withRenderingMode(.alwaysTemplate),
                                        accessoryImage: nil,
                                        accessoryType: .disclosureIndicator)
        favouritesItem.handler = { [weak self] _, completion in
            self?.pushFavouritesTemplate()
            completion()
        }

        let radioItem = CPListItem(text: "Radio",
                                   detailText: "Stream modules from AMP",
                                   image: UIImage(named: "radio")?.withRenderingMode(.alwaysTemplate),
                                   accessoryImage: nil,
                                   accessoryType: .disclosureIndicator)
        radioItem.handler = { [weak self] _, completion in
            self?.pushRadioTemplate()
            completion()
        }

        return CPListTemplate(title: "4champ", sections: [CPListSection(items: [favouritesItem, radioItem])])
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
            let all = try moduleStorage.managedObjectContext.fetch(request)
            return all
                .filter { $0.radioOnly == nil || $0.radioOnly?.intValue == 0 }
                .map(MMD.init)
                .sorted {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare(
                            $1.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ) == .orderedAscending
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
