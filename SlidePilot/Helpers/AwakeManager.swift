//
//  AwakeManager.swift
//  SlidePilot
//
//  Created by Pascal Braband on 23.06.20.
//  Copyright © 2020 Pascal Braband. All rights reserved.
//

import IOKit.pwr_mgt

class AwakeManager {

    /** The ID of the assertion that keeps the display on, while it is held. */
    private var noSleepAssertionID: IOPMAssertionID?


    /**
     Keeps the display on, which also keeps the screen saver from starting and the Mac from going to sleep when idle.

     - returns: Whether the display is kept on.
     */
    @discardableResult
    public func disableScreenSleep(reason: String = "Keep Mac awake during presentations.") -> Bool {
        guard noSleepAssertionID == nil else { return true }
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString,
                                                 &assertionID)
        guard result == kIOReturnSuccess else { return false }
        noSleepAssertionID = assertionID
        return true
    }


    /** Lets the display sleep and the screen saver start again. */
    public func enableScreenSleep() {
        guard let assertionID = noSleepAssertionID else { return }
        IOPMAssertionRelease(assertionID)
        noSleepAssertionID = nil
    }

}
