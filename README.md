# SlidePilot Typst

<p align="center">
  <img width=120 src="Icon/AppIcon.svg"/>
</p>
<p align="center">
  <strong>PDF presentation tool for macOS that plays the videos and GIFs in your Typst slides 🖥</strong>
</p>

This is a personal fork of [SlidePilot](https://github.com/SlidePilot/SlidePilot-macOS) by Pascal Braband. It keeps everything SlidePilot does, such as the presenter display, notes, timer, drawing and pointer, and adds:

- **Videos and GIFs from Typst.** Media embedded with the [presio](https://typst.app/universe/package/presio) package play right on the slide.
- **No cursor during the presentation.** In the fullscreen presentation window the mouse cursor hides after 2 seconds without moving. It stays visible while the pointer is shown.
- **A new app icon**, drawn as an SVG in [`Icon/`](Icon).

The cursor hiding was inspired by the [tce/SlidePilot-macOS](https://github.com/tce/SlidePilot-macOS) fork.

## Videos and GIFs in Typst slides

PDF files can't play videos by themselves. presio solves this by attaching each media file to the PDF together with its position on the slide, and SlidePilot reads these attachments and plays them over the slide. Other PDF viewers show the placeholder instead.

presio needs Typst 0.15 or later.

```typst
#import "@preview/presio:0.2.3": media

// Starts playing when the slide appears and loops
#media(path("demo.mp4"), width: 60%, placeholder: image("poster.png", width: 100%))

// Waits for a click and plays once
#media(path("demo.mp4"), width: 60%, autoplay: false, loop: false)

// GIFs work the same way
#media(path("spinner.gif"), width: 3cm, placeholder: image("spinner.gif", width: 3cm))
```

How the media behaves in SlidePilot:

- Media only plays on the current slide. Thumbnails, the next-slide preview and the notes show the placeholder.
- The presenter display and the presentation window share one player for each video and GIF, so pausing it on one screen pauses it on the other. Videos have the usual playback controls, and clicking a GIF plays or pauses it.
- When the same media is on consecutive pages, for example on overlay steps, it keeps playing instead of restarting.
- The arrow keys and Page Up/Down change slides even after you click a video.
- The `autoplay` and `loop` options of presio are respected for videos and GIFs.
- Videos need a format macOS can play, such as MP4 or MOV with H.264 or HEVC. WebM isn't supported, and YouTube and Vimeo links aren't played. For these, the slide shows its placeholder.

Movies embedded with the LaTeX `multimedia` package keep working as in SlidePilot.

## Building

SlidePilot Typst requires macOS 12 or later. Open `SlidePilot.xcodeproj` in Xcode and run the `SlidePilot` scheme. There are no prebuilt downloads.

### App icon

The icon is drawn in [`Icon/AppIcon.svg`](Icon/AppIcon.svg). After changing it, render all sizes of the app icon set from the repository root:

```sh
swift Icon/render-app-icon.swift
```

## Original SlidePilot

- [Website and downloads](https://www.slidepilotapp.com)
- [Documentation](https://slidepilot.gitbook.io/slidepilot/)
- [Features & Changelog](https://slidepilot.gitbook.io/slidepilot/changelog)

## License

SlidePilot is licensed under the [GNU General Public License v3.0](LICENSE), and so is this fork.
