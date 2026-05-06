//HardwareController.swift
//  Created by Michael Houlder on 2026-03-04.
//

import Foundation
import Combine

@MainActor
final class HardwareController: ObservableObject {

    let objectWillChange = ObservableObjectPublisher()

    let motion = MotionManager()

    private(set) var isForeground: Bool = true

    func setForeground(_ foreground: Bool) {
        isForeground = foreground

        if foreground {
            motion.start()
        } else {
            motion.stop()
        }

        objectWillChange.send()
    }

    func setRadarActive(_ active: Bool, displayName: String, team: TacticalTeam) {
        guard isForeground else { return }
        objectWillChange.send()
    }
}
