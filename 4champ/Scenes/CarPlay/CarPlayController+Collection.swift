//
//  CarPlayController+Collection.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay
import CoreData

extension CarPlayController {

    // MARK: - Collection navigation

    func pushFavouritesTemplate() {
        let template = CPListTemplate(title: "Collection", sections: makeCollectionSections())
        collectionTemplate = template
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    func makeCollectionSections() -> [CPListSection] {
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
