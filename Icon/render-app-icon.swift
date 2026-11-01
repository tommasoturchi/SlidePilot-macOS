// Renders AppIcon.svg into every PNG of the app icon set, using WebKit to draw the SVG.
//
// Run from the repository root:
//   swift Icon/render-app-icon.swift [path/to/icon.svg] [path/to/AppIcon.appiconset]

import AppKit
import WebKit

let arguments = CommandLine.arguments
let svgURL = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "Icon/AppIcon.svg")
let iconSetURL = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "SlidePilot/Assets.xcassets/AppIcon.appiconset")

struct IconSet: Decodable {
    struct Image: Decodable {
        let filename: String?
        let size: String
        let scale: String
    }
    let images: [Image]
}

/** Pixel sizes by file name, as listed in the icon set's Contents.json. */
func iconFiles() throws -> [(name: String, pixels: Int)] {
    let data = try Data(contentsOf: iconSetURL.appendingPathComponent("Contents.json"))
    return try JSONDecoder().decode(IconSet.self, from: data).images.compactMap { image in
        guard let name = image.filename,
              let points = Double(image.size.split(separator: "x")[0]),
              let scale = Double(image.scale.dropLast()) else { return nil }
        return (name, Int(points * scale))
    }
}

final class Renderer: NSObject, WKNavigationDelegate {
    private let canvas = 1024
    private let webView: WKWebView
    private var pending: [(name: String, pixels: Int)]

    init(files: [(name: String, pixels: Int)]) {
        pending = files
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: canvas, height: canvas))
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
    }

    func start() throws {
        let svg = try Data(contentsOf: svgURL).base64EncodedString()
        let html = """
        <html><body style="margin:0;background:transparent">
        <img src="data:image/svg+xml;base64,\(svg)" style="display:block;width:\(canvas)px;height:\(canvas)px">
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        renderNext()
    }

    private func renderNext() {
        guard let file = pending.first else { exit(0) }
        pending.removeFirst()

        // The snapshot is scaled down from the vector rendering, so small sizes stay sharp
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: file.pixels)
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image = image else { fatalError("Snapshot failed: \(String(describing: error))") }
            self.write(image, pixels: file.pixels, to: iconSetURL.appendingPathComponent(file.name))
            print("\(file.name): \(file.pixels)×\(file.pixels)")
            self.renderNext()
        }
    }

    private func write(_ image: NSImage, pixels: Int, to url: URL) {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

let renderer = Renderer(files: try iconFiles())
try renderer.start()
RunLoop.main.run()
