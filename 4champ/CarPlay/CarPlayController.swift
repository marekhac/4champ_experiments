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

    weak var interfaceController: CPInterfaceController?
    var fetcher: ModuleFetcher?
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
        let favouritesItem = CPListItem(text: "Favourites",
                                         detailText: "Your starred modules",
                                         image: UIImage(named: "localMods"),
                                         showsDisclosureIndicator: true)
        favouritesItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.pushFavouritesTemplate() }
            done()
        }
        let radioItem = CPListItem(text: "Radio",
                                   detailText: "Stream modules from AMP",
                                   image: UIImage(named: "radio"),
                                   showsDisclosureIndicator: true)
        radioItem.handler = { [weak self] _, done in
            DispatchQueue.main.async { self?.pushRadioTemplate() }
            done()
        }
        return CPListTemplate(title: "4champ", sections: [CPListSection(items: [favouritesItem, radioItem])])
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

    private func pushFavouritesTemplate() {
        let favourites = fetchFavourites()
        let items: [CPListItem]
        if favourites.isEmpty {
            items = [CPListItem(text: "No favourites yet", detailText: nil)]
        } else {
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
        let request = ModuleInfo.fetchRequest()
        request.predicate = NSPredicate(format: "modFavorite == 1")
        request.sortDescriptors = [NSSortDescriptor(key: "modName", ascending: true,
                                                     selector: #selector(NSString.caseInsensitiveCompare))]
        let frc = moduleStorage.createFRC(fetchRequest: request, entityName: "ModuleInfo")
        try? frc.performFetch()
        return frc.fetchedObjects?.compactMap { MMD(cdi: $0) } ?? []
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
