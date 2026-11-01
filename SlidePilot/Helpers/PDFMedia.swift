//
//  PDFMedia.swift
//  SlidePilot
//

import Cocoa
import PDFKit

/** A video or animated image, which is played on top of a PDF page. */
struct PDFMedia {
    
    /** Location of the media file. Media embedded in the PDF is extracted to a temporary file. */
    let url: URL
    
    /** Position of the media on the page, in PDF page coordinates. */
    let bounds: CGRect
    
    let autoplay: Bool
    let loops: Bool
    
    /** Animated images are shown in an image view, because AVPlayer can't play them. */
    var isAnimatedImage: Bool {
        return url.pathExtension.lowercased() == "gif"
    }
}




extension PDFDocument {
    
    /** Returns the media, that should be played on the page at the given index. */
    func media(onPage index: Int) -> [PDFMedia] {
        guard let page = self.page(at: index) else { return [] }
        return page.movieAnnotationMedia(relativeTo: documentURL) + PDFMediaLibrary.shared.attachedMedia(onPage: index, of: self)
    }
}




extension PDFPage {
    
    /** Returns media from movie annotations, such as the ones created by the LaTeX multimedia package. */
    func movieAnnotationMedia(relativeTo documentURL: URL?) -> [PDFMedia] {
        return annotations.filter({ $0.type == "Movie" }).compactMap { annotation in
            guard let movieValues = annotation.annotationKeyValues["/Movie"] as? [AnyHashable: Any] else { return nil }
            guard let fileName = movieValues.values.first as? String else { return nil }
            guard let movieURL = URL(string: fileName, relativeTo: documentURL) else { return nil }
            return PDFMedia(url: movieURL, bounds: annotation.bounds, autoplay: false, loops: false)
        }
    }
}




/**
 Reads media attached by the presio Typst package (https://typst.app/universe/package/presio).
 
 presio attaches every media file to the PDF, together with a `media-slide-<page>-<id>.json` descriptor, which contains the placement of the media on the page.
 */
class PDFMediaLibrary {
    
    static let shared = PDFMediaLibrary()
    
    private weak var document: PDFDocument?
    
    /** Embedded files of the current document by their name. The streams are only valid while `documentRef` is retained. */
    private var documentRef: CGPDFDocument?
    private var embeddedFiles = [String: CGPDFStreamRef]()
    private var descriptors = [Int: [MediaDescriptor]]()
    private var extractedFiles = [String: URL]()
    
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlidePilot Media", isDirectory: true)
    
    
    func attachedMedia(onPage index: Int, of document: PDFDocument) -> [PDFMedia] {
        if self.document !== document {
            load(document)
        }
        
        guard let page = document.page(at: index), let pageDescriptors = descriptors[index] else { return [] }
        let mediaBox = page.bounds(for: .mediaBox)
        
        return pageDescriptors.compactMap { descriptor in
            guard let url = url(for: descriptor) else { return nil }
            // presio measures from the top left corner of the page, PDF coordinates start at the bottom left
            let bounds = CGRect(x: mediaBox.minX + descriptor.x,
                                y: mediaBox.maxY - descriptor.y - descriptor.height,
                                width: descriptor.width,
                                height: descriptor.height)
            return PDFMedia(url: url, bounds: bounds, autoplay: descriptor.autoplay ?? true, loops: descriptor.loop ?? true)
        }
    }
    
    
    private func load(_ document: PDFDocument) {
        self.document = document
        documentRef = document.documentRef
        embeddedFiles = [:]
        descriptors = [:]
        extractedFiles = [:]
        try? FileManager.default.removeItem(at: directory)
        
        // Embedded files are listed in the name tree at /Root /Names /EmbeddedFiles
        guard let catalog = documentRef?.catalog else { return }
        var names: CGPDFDictionaryRef?
        var embeddedFilesTree: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &names), let namesDictionary = names,
              CGPDFDictionaryGetDictionary(namesDictionary, "EmbeddedFiles", &embeddedFilesTree), let tree = embeddedFilesTree else { return }
        collectEmbeddedFiles(in: tree)
        
        for (name, stream) in embeddedFiles where name.hasPrefix("media-slide-") && name.hasSuffix(".json") {
            guard let data = Self.data(of: stream),
                  let descriptor = try? JSONDecoder().decode(MediaDescriptor.self, from: data) else { continue }
            // presio counts pages starting at 1
            descriptors[descriptor.slide - 1, default: []].append(descriptor)
        }
    }
    
    
    /** Adds all files of the name tree node and its children to `embeddedFiles`. */
    private func collectEmbeddedFiles(in node: CGPDFDictionaryRef, depth: Int = 0) {
        var names: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &names), let namesArray = names {
            // The array alternates between the file name and its file specification
            for index in stride(from: 0, to: CGPDFArrayGetCount(namesArray) - 1, by: 2) {
                var name: CGPDFStringRef?
                var fileSpecification: CGPDFDictionaryRef?
                var embeddedFile: CGPDFDictionaryRef?
                var stream: CGPDFStreamRef?
                guard CGPDFArrayGetString(namesArray, index, &name), let nameString = name.flatMap(CGPDFStringCopyTextString),
                      CGPDFArrayGetDictionary(namesArray, index + 1, &fileSpecification), let specification = fileSpecification,
                      CGPDFDictionaryGetDictionary(specification, "EF", &embeddedFile), let embeddedFileDictionary = embeddedFile,
                      CGPDFDictionaryGetStream(embeddedFileDictionary, "F", &stream) || CGPDFDictionaryGetStream(embeddedFileDictionary, "UF", &stream),
                      let fileStream = stream else { continue }
                // Typst prefixes the name with the path of the file calling pdf.attach, e.g. "src/media-demo_gif.gif"
                embeddedFiles[(nameString as NSString).lastPathComponent] = fileStream
            }
        }
        
        // Guard against cyclic trees in malformed documents
        guard depth < 32 else { return }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kidsArray = kids {
            for index in 0..<CGPDFArrayGetCount(kidsArray) {
                var kid: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(kidsArray, index, &kid), let kidDictionary = kid else { continue }
                collectEmbeddedFiles(in: kidDictionary, depth: depth + 1)
            }
        }
    }
    
    
    private func url(for descriptor: MediaDescriptor) -> URL? {
        switch descriptor.kind {
        case "file":
            guard let filename = descriptor.filename else { return nil }
            return extractedFile(named: filename)
        case "url":
            guard let url = descriptor.url.flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
            return url
        default:
            // YouTube and Vimeo pages can't be played by AVPlayer
            return nil
        }
    }
    
    
    /** Writes the embedded file to a temporary file, so that it can be played. */
    private func extractedFile(named name: String) -> URL? {
        let fileName = (name as NSString).lastPathComponent
        if let url = extractedFiles[fileName] { return url }
        guard let stream = embeddedFiles[fileName], let data = Self.data(of: stream) else { return nil }
        
        let url = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        extractedFiles[fileName] = url
        return url
    }
    
    
    private static func data(of stream: CGPDFStreamRef) -> Data? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
        return data as Data
    }
    
    
    /** Placement of a media file, as written by presio. Lengths are in points, measured from the top left corner of the page. */
    private struct MediaDescriptor: Decodable {
        let kind: String
        let slide: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let autoplay: Bool?
        let loop: Bool?
        let filename: String?
        let url: String?
        
        enum CodingKeys: String, CodingKey {
            case kind, slide, autoplay, loop, filename, url
            case x = "x_pt", y = "y_pt", width = "w_pt", height = "h_pt"
        }
    }
}
