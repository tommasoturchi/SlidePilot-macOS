//
//  DocumentReloadTests.swift
//  SlidePilotTests
//

import XCTest
import PDFKit
@testable import SlidePilot

class DocumentReloadTests: XCTestCase {
    
    private var directory: URL!
    private var file: URL!
    private var observer: FileObserver?
    private var changes = 0
    private var changeExpectation: XCTestExpectation?
    
    
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("slides.pdf")
        try Data("first".utf8).write(to: file)
    }
    
    
    override func tearDownWithError() throws {
        observer = nil
        PageController.enablePageSwitching(true, sender: self)
        try FileManager.default.removeItem(at: directory)
    }
    
    
    private func startObserving() {
        changes = 0
        observer = FileObserver(URL: file) { [weak self] in
            DispatchQueue.main.async {
                self?.changes += 1
                self?.changeExpectation?.fulfill()
                self?.changeExpectation = nil
            }
        }
    }
    
    
    private func waitForChange(after change: () throws -> Void) rethrows {
        let expectation = self.expectation(description: "File change was reported")
        changeExpectation = expectation
        try change()
        wait(for: [expectation], timeout: 3)
    }
    
    
    private func waitWithoutChange(after change: () throws -> Void) rethrows {
        let changesBefore = changes
        try change()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        XCTAssertEqual(changes, changesBefore)
    }
    
    
    private func writeInPlace(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }
    
    
    private func replaceByRenaming(_ text: String) throws {
        let temporaryFile = directory.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: temporaryFile)
        XCTAssertEqual(rename(temporaryFile.path, file.path), 0)
    }
    
    
    func testReportsWriteInPlace() throws {
        startObserving()
        try waitForChange { try writeInPlace("second") }
    }
    
    
    func testReportsAtomicSave() throws {
        startObserving()
        try waitForChange { try Data("second".utf8).write(to: file, options: .atomic) }
    }
    
    
    func testKeepsFollowingAfterReplacement() throws {
        startObserving()
        try waitForChange { try replaceByRenaming("second") }
        try waitForChange { try replaceByRenaming("third") }
        try waitForChange { try writeInPlace("fourth") }
    }
    
    
    func testReportsFileRecreatedLater() throws {
        startObserving()
        try waitWithoutChange { try FileManager.default.removeItem(at: file) }
        try waitForChange { try Data("second".utf8).write(to: file) }
        try waitForChange { try writeInPlace("third") }
    }
    
    
    func testReportsBurstOfWritesOnce() throws {
        startObserving()
        try waitForChange {
            for index in 0..<5 {
                try writeInPlace("write \(index)")
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        XCTAssertEqual(changes, 1)
    }
    
    
    func testIgnoresOtherFilesInDirectory() throws {
        startObserving()
        try waitWithoutChange {
            try Data("other".utf8).write(to: directory.appendingPathComponent("slides.aux"))
        }
    }
    
    
    private func document(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            document.insert(PDFPage(), at: index)
        }
        return document
    }
    
    
    func testRestoreKeepsPageWhilePageSwitchingIsDisabled() {
        DocumentController.setDocument(document(pageCount: 5), sender: self)
        PageController.selectPage(at: 3, sender: self)
        PageController.enablePageSwitching(false, sender: self)
        
        let notification = expectation(forNotification: .didSelectPage, object: nil)
        DocumentController.setDocument(document(pageCount: 5), sender: self)
        PageController.restoreCurrentPage(sender: self)
        
        wait(for: [notification], timeout: 1)
        XCTAssertEqual(PageController.currentPage, 3)
    }
    
    
    func testRestoreSelectsLastPageOfShorterDocument() {
        DocumentController.setDocument(document(pageCount: 5), sender: self)
        PageController.selectPage(at: 1, sender: self)
        PageController.selectPage(at: 4, sender: self)
        
        DocumentController.setDocument(document(pageCount: 2), sender: self)
        PageController.restoreCurrentPage(sender: self)
        
        XCTAssertEqual(PageController.currentPage, 1)
        XCTAssertEqual(PageController.previousPage, 1)
    }
    
}
