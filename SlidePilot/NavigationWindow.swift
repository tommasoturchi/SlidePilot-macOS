//
//  NavigationWindow.swift
//  SlidePilot
//
//  Created by Pascal Braband on 18.05.20.
//  Copyright © 2020 Pascal Braband. All rights reserved.
//

import Cocoa

class NavigationWindow: NSWindow {
    
    override func sendEvent(_ event: NSEvent) {
        // Video player controls use the arrow keys for seeking, so navigate the slides before they receive the keys
        if event.type == .keyDown,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           isNavigationKey(event),
           isVideoPlayerFocused() {
            keyDown(with: event)
            return
        }
        super.sendEvent(event)
    }
    
    
    private func isNavigationKey(_ event: NSEvent) -> Bool {
        return [123, 124, 125, 126].contains(event.keyCode) || event.specialKey == NSEvent.SpecialKey.pageUp || event.specialKey == NSEvent.SpecialKey.pageDown
    }
    
    
    private func isVideoPlayerFocused() -> Bool {
        var responder = firstResponder
        while let current = responder {
            if current is ConnectedPlayer { return true }
            responder = current.nextResponder
        }
        return false
    }
    
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 126 || event.specialKey == NSEvent.SpecialKey.pageUp {
            PageController.previousPage(sender: self)
        } else if event.keyCode == 124 || event.keyCode == 125 || event.specialKey == NSEvent.SpecialKey.pageDown {
            PageController.nextPage(sender: self)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.startTimerIfNeeded()
            }
        } else {
            super.keyDown(with: event)
        }
    }

}
