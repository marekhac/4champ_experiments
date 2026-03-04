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
        setupRemoteCommands()
    }

    deinit {
        teardownRemoteCommands()
        modulePlayer.removePlayerObserver(self)
        radioFetchers.forEach { $0.cancel() }
    }

    // MARK: - Root template

    func makeRootTemplate() -> CPListTemplate {
        let favouritesItem = CPListItem(text: "Favourites",
                                        detailText: "Your starred modules",
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
        let favourites = fetchFavourites()
        let items: [CPListItem]
        if favourites.isEmpty {
            items = [CPListItem(text: "No favourites yet", detailText: nil)]
        } else {
            // Create interactive list items for each favourite module
            items = favourites.map { mmd in
                let item = CPListItem(text: mmd.name,
                                      detailText: mmd.composer,
                                      image: moduleIcon(for: mmd))
                item.handler = { [weak self] _, done in
                    DispatchQueue.main.async { self?.playOrFetch(mmd: mmd) }
                    done()
                }
                return item
            }
        }
        let template = CPListTemplate(title: "Favourites", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    private func fetchFavourites() -> [MMD] {
        let request: NSFetchRequest<ModuleInfo> = ModuleInfo.fetchRequest()

        // Only modules marked as favourite
        request.predicate = NSPredicate(format: "modFavorite == YES")

        // Alphabetical sort ignoring case differences
        request.sortDescriptors = [
            NSSortDescriptor(
                key: #keyPath(ModuleInfo.modName),
                ascending: true,
                selector: #selector(NSString.caseInsensitiveCompare)
            )
        ]

        let frc = moduleStorage.createFRC(
            fetchRequest: request,
            entityName: ModuleInfo.entity().name ?? "ModuleInfo"
        )

        do {
            try frc.performFetch()

            // Convert Core Data objects into immutable domain models
            return frc.fetchedObjects?.map(MMD.init) ?? []
        } catch {
            assertionFailure("Failed to fetch favourites: \(error)")
            return []
        }
    }

    private func playOrFetch(mmd: MMD) {
        // Fast path: file already exists locally
        if mmd.fileExists() {
            modulePlayer.play(mmd: mmd)
            return
        }

        // Cannot fetch without a remote identifier
        guard let id = mmd.id else { return }

        fetcher?.cancel()
        fetcher = ModuleFetcher(delegate: self)
        fetcher?.fetchModule(ampId: id)
    }
}
