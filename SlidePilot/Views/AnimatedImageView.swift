//
//  AnimatedImageView.swift
//  SlidePilot
//

import Cocoa
import ImageIO

/**
 Plays the frames of an animated image, such as a GIF.

 All views showing the same image share one player, so that the presenter display and the presentation window show the same frame and are paused together.
 */
class AnimatedImagePlayer {
    
    static let frameDidChangeNotification = Notification.Name(rawValue: "animatedImagePlayerFrameDidChangeNotification")
    
    /** Players by the URL of their image. A player is only kept, as long as a view shows it. */
    private static let players = NSMapTable<NSURL, AnimatedImagePlayer>.strongToWeakObjects()
    
    private let source: CGImageSource
    private let frameDurations: [TimeInterval]
    private let loops: Bool
    private var frameIndex = 0
    private var timer: Timer?
    
    private(set) var currentFrame: CGImage?
    
    var isPlaying: Bool {
        return timer != nil
    }
    
    
    /** Returns the player, which is currently showing the media, or creates a new one. */
    static func player(for media: PDFMedia) -> AnimatedImagePlayer? {
        if let player = players.object(forKey: media.url as NSURL) {
            return player
        }
        
        guard let player = AnimatedImagePlayer(url: media.url, loops: media.loops) else { return nil }
        players.setObject(player, forKey: media.url as NSURL)
        if media.autoplay {
            player.play()
        }
        return player
    }
    
    
    private init?(url: URL, loops: Bool) {
        // Read the whole file, so that the player doesn't depend on the extracted file
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        self.source = source
        self.loops = loops
        frameDurations = (0..<CGImageSourceGetCount(source)).map { Self.duration(ofFrame: $0, in: source) }
        currentFrame = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    
    
    deinit {
        timer?.invalidate()
    }
    
    
    func play() {
        guard !isPlaying, frameDurations.count > 1 else { return }
        
        // Start over, if the animation doesn't loop and has ended
        if !loops && frameIndex == frameDurations.count - 1 {
            showFrame(0)
        }
        scheduleNextFrame()
    }
    
    
    func pause() {
        timer?.invalidate()
        timer = nil
    }
    
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    
    private func scheduleNextFrame() {
        let timer = Timer(timeInterval: frameDurations[frameIndex], repeats: false) { [weak self] _ in
            self?.showNextFrame()
        }
        // Keep animating while a menu is open
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    
    private func showNextFrame() {
        timer = nil
        
        // Animations, that don't loop, stop on their last frame
        if !loops && frameIndex == frameDurations.count - 1 {
            return
        }
        showFrame((frameIndex + 1) % frameDurations.count)
        scheduleNextFrame()
    }
    
    
    private func showFrame(_ index: Int) {
        frameIndex = index
        currentFrame = CGImageSourceCreateImageAtIndex(source, index, nil)
        NotificationCenter.default.post(name: Self.frameDidChangeNotification, object: self)
    }
    
    
    /** Returns how long the frame is shown. Like web browsers, very short delays are shown for 0.1 seconds. */
    private static func duration(ofFrame index: Int, in source: CGImageSource) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let delay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
            ?? gifProperties?[kCGImagePropertyGIFDelayTime as String] as? Double
            ?? 0
        return delay <= 0.01 ? 0.1 : delay
    }
}




/** Shows the current frame of an animated image player. Clicking the view pauses or resumes the animation. */
class AnimatedImageView: NSView {
    
    let player: AnimatedImagePlayer
    
    init(player: AnimatedImagePlayer) {
        self.player = player
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange), name: AnimatedImagePlayer.frameDidChangeNotification, object: player)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    
    override func updateLayer() {
        layer?.contents = player.currentFrame
    }
    
    
    @objc private func frameDidChange() {
        needsDisplay = true
    }
    
    
    override func mouseDown(with event: NSEvent) {
        player.togglePlayback()
    }
}
