//
//  CarPlayController+PlaybackEvents.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import CarPlay

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
            guard isRadioActive else { return }
            modulePlayer.playQueue.append(mmd)
            if modulePlayer.playQueue.first == mmd { modulePlayer.play(at: 0) }
            fillRadioBuffer()
        case .failed:
            radioFetchers.removeAll { $0 === fetcher }
            if isRadioActive { fillRadioBuffer() }
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
            if self.isRadioActive {
                switch self.radioChannel {
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
