//
//  CarPlayController+RemoteCommands.swift
//  4champ Amiga Music Player
//
//  Copyright © 2026 Marek Hac. All rights reserved.
//

import MediaPlayer

extension CarPlayController {

    // MARK: - Remote command centre

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        registerCommand(center.playCommand) { modulePlayer.resume() }
        registerCommand(center.pauseCommand) { modulePlayer.pause() }
        registerCommand(center.stopCommand) { modulePlayer.stop() }
        registerCommand(center.nextTrackCommand) { modulePlayer.playNext() }
        registerCommand(center.previousTrackCommand) { modulePlayer.playPrev() }
    }

    func teardownRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
    }

    private func registerCommand(_ command: MPRemoteCommand, action: @escaping () -> Void) {
        command.isEnabled = true
        command.addTarget { _ in
            action()
            return .success
        }
    }
}
