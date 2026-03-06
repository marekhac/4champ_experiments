//
//  CarPlayController.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay
import Foundation
import UIKit

class CarPlayController: NSObject {

    // MARK: - Dependencies

    weak var interfaceController: CPInterfaceController?
    var fetcher: ModuleFetcher?

    // MARK: - Templates

    var nowPlayingTemplate: CPListTemplate?
    var collectionTemplate: CPListTemplate?

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
}
