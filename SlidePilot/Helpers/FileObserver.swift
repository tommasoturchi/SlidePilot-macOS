//
//  FileObserver.swift
//  SlidePilot
//
//  Created by Pascal Braband on 05.10.20.
//  Copyright © 2020 Pascal Braband. All rights reserved.
//

import Cocoa

/**
 Calls a block when the file at a URL changes, however it was saved.
 
 Writing to the file in place is seen by watching the file itself. Many apps replace the file instead, by renaming a temporary file over it, or delete and recreate it. The watched file is gone then, so the directory is watched as well, to find the new file at the same path.
 */
class FileObserver {
    
    /** Identifies one saved state of a file. */
    private struct Version: Equatable {
        let fileNumber: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
    }
    
    /** A save is considered finished after this time without further changes, so that half written files are not reported. */
    private static let settleDelay: TimeInterval = 0.3
    
    let url: URL
    
    private let block: () -> Void
    private let queue = DispatchQueue(label: "FileObserver")
    
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFileNumber: UInt64?
    private var lastVersion: Version?
    private var pendingCheck: DispatchWorkItem?
    
    
    deinit {
        pendingCheck?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
    }
    
    
    init(URL: URL, block: @escaping ()->Void) {
        self.url = URL
        self.block = block
        
        queue.sync {
            lastVersion = currentVersion()
            directorySource = makeSource(path: URL.deletingLastPathComponent().path, eventMask: .write) { [weak self] in
                // Other files in the directory may change all the time, only a different file at the path is relevant
                if self?.watchNewFileIfReplaced() == true {
                    self?.scheduleCheck()
                }
            }
            watchFile()
        }
    }
    
    
    private func makeSource(path: String, eventMask: DispatchSource.FileSystemEvent, handler: @escaping ()->Void) -> DispatchSourceFileSystemObject? {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }
        
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: eventMask, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        return source
    }
    
    
    private func watchFile() {
        // Read before opening, so that a replacement in between is noticed as a different file later on
        watchedFileNumber = currentVersion()?.fileNumber
        
        fileSource?.cancel()
        fileSource = makeSource(path: url.path, eventMask: [.write, .delete, .rename]) { [weak self] in
            self?.watchNewFileIfReplaced()
            self?.scheduleCheck()
        }
    }
    
    
    /** Starts watching the file which is now at the path, if it is not the watched one anymore. Returns whether that was the case. */
    @discardableResult private func watchNewFileIfReplaced() -> Bool {
        guard currentVersion()?.fileNumber != watchedFileNumber else { return false }
        watchFile()
        return true
    }
    
    
    private func scheduleCheck() {
        pendingCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            self?.reportChange()
        }
        pendingCheck = check
        queue.asyncAfter(deadline: .now() + FileObserver.settleDelay, execute: check)
    }
    
    
    private func reportChange() {
        // A file which is recreated may be missing for a while, the directory reports when it is back
        guard let version = currentVersion(), version != lastVersion else { return }
        lastVersion = version
        block()
    }
    
    
    private func currentVersion() -> Version? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Version(fileNumber: info.st_ino,
                       size: info.st_size,
                       modifiedSeconds: info.st_mtimespec.tv_sec,
                       modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }
    
}
