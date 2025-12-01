# DrawThingsVideoKit

A Swift package that extends [DrawThingsKit](https://github.com/euphoriacyberware-ai/DrawThingsKit) with video assembly capabilities, allowing you to create videos from generated image sequences.

## Requirements

- macOS 14.0+ / iOS 17.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add DrawThingsVideoKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/euphoriacyberware-ai/DrawThingsVideoKit", from: "1.0.0")
]
```

Or add it in Xcode via File → Add Package Dependencies.

## Key Components

### VideoConfiguration

Settings for video output including codec, quality, and frame rate:

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    frameRate: 16,  // Default matches Draw Things output
    codec: .h264,
    quality: .high,
    interpolation: .enabled(factor: 2)
)
```

**Properties:**
- `outputURL: URL` - Destination for the video file
- `frameRate: Int` - Target frame rate (default: 16, matching Draw Things output)
- `codec: VideoCodec` - Video codec (.h264, .hevc, .proRes422, .proRes4444)
- `quality: VideoQuality` - Encoding quality (.low, .medium, .high, .maximum)
- `interpolation: InterpolationMode` - Frame interpolation (.disabled or .enabled(factor:))
- `overwriteExisting: Bool` - Whether to overwrite existing files (default: true)
- `audioURL: URL?` - Optional audio track (planned for future release)

### VideoFrameCollection

A standardized container for video frames that supports multiple image formats:

```swift
// From URLs
let collection = VideoFrameCollection(urls: frameURLs)

// From CGImages
let collection = VideoFrameCollection(cgImages: images)

// From platform images (NSImage/UIImage)
let collection = VideoFrameCollection(images: platformImages)

// Build incrementally
var collection = VideoFrameCollection()
collection.append(url: imageURL)
collection.append(cgImage: cgImage)

// Remove frames
collection.remove(at: IndexSet([0, 2, 5]))
```

### VideoAssembler

Low-level frame-to-video assembly using AVFoundation:

```swift
let assembler = VideoAssembler()

let outputURL = try await assembler.assemble(
    frames: frameCollection,
    configuration: config
) { progress in
    print("Progress: \(progress * 100)%")
}
```

### VideoProcessor

High-level coordinator that integrates with DrawThingsKit's JobQueue. Supports two modes of operation:

#### Automatic Mode (Recommended)

Subscribes to JobQueue events and automatically assembles videos when video jobs complete:

```swift
// Create a configuration provider for dynamic per-job output URLs
let configProvider: VideoConfigurationProvider = { jobId in
    let outputURL = outputDirectory.appendingPathComponent("\(jobId).mp4")
    return VideoConfiguration(
        outputURL: outputURL,
        frameRate: 16,
        codec: .h264,
        quality: .high
    )
}

// Create processor with auto-assembly enabled
let processor = VideoProcessor(
    configuration: VideoProcessorConfiguration(
        autoAssemble: true,
        minimumFrames: 2,
        defaultVideoConfiguration: defaultConfig,
        collectAllCompletedJobs: false,  // Only collect video jobs (numFrames > 1)
        configurationProvider: configProvider
    )
)

// Subscribe to events
processor.events
    .sink { event in
        switch event {
        case .assemblyStarted(let jobId):
            print("Assembly started for \(jobId)")
        case .assemblyProgress(let jobId, let progress):
            print("Progress: \(Int(progress * 100))%")
        case .assemblyCompleted(let jobId, let url):
            print("Video saved to: \(url)")
        case .assemblyFailed(let jobId, let error):
            print("Assembly failed: \(error)")
        case .framesCollected(let jobId, let count):
            print("Collected \(count) frames from \(jobId)")
        }
    }
    .store(in: &cancellables)

// Connect to job queue - processor will automatically handle video jobs
processor.connect(to: queue)
```

#### Manual Mode

For more control, disable auto-assembly and trigger manually:

```swift
let processor = VideoProcessor(
    configuration: VideoProcessorConfiguration(
        autoAssemble: false,
        minimumFrames: 2,
        defaultVideoConfiguration: videoConfig
    )
)

// Manually add frames
processor.addFrames(from: images, job: job)

// Or add from URLs
processor.addFrames(from: imageURLs)

// Remove unwanted frames
processor.removeFrames(at: IndexSet([0, 5]))

// Assemble when ready
let outputURL = try await processor.assembleCollectedFrames()

// Clear for next batch
processor.clearFrames()
```

## UI Components

### VideoConfigurationView

SwiftUI view for configuring video output settings:

```swift
@State private var frameRate: Int = 16
@State private var codec: VideoCodec = .h264
@State private var quality: VideoQuality = .high
@State private var interpolationEnabled: Bool = false
@State private var interpolationFactor: Int = 2

VideoConfigurationView(
    frameRate: $frameRate,
    codec: $codec,
    quality: $quality,
    interpolationEnabled: $interpolationEnabled,
    interpolationFactor: $interpolationFactor
)
```

Provides pickers for:
- Frame rate (12, 15, 16, 24, 30, 60 fps)
- Video codec (H.264, HEVC, ProRes 422, ProRes 4444)
- Quality preset (Low, Medium, High, Maximum)
- Frame interpolation toggle and multiplier (2x, 3x, 4x)

### VideoAssemblyProgressView

Displays video assembly progress and status:

```swift
VideoAssemblyProgressView(processor: processor) { outputURL in
    // Video is ready - open in Finder, preview, etc.
    print("Video saved to: \(outputURL)")
}
```

Shows:
- Progress bar during assembly with percentage
- Stage indicator (interpolating vs encoding)
- Completion status with "Show in Finder" button (macOS)
- Error display on failure
- Frame count when ready to assemble

### VideoFrameCollectionView

Displays collected frames with thumbnails and selection support:

```swift
VideoFrameCollectionView(
    frames: processor.collectedFrames,
    thumbnailSize: 80
) { indicesToRemove in
    processor.removeFrames(at: indicesToRemove)
}
```

Features:
- Horizontal scrolling thumbnail grid
- Frame count indicator
- Tap to select/deselect frames
- "Remove N" button appears when frames are selected
- "Deselect" button to clear selection

## Complete Example

```swift
import SwiftUI
import DrawThingsKit
import DrawThingsVideoKit
import Combine

@MainActor
class VideoSettings: ObservableObject {
    @Published var videoModeEnabled = false
    @Published var frameRate = 16
    @Published var codec: VideoCodec = .h264
    @Published var quality: VideoQuality = .high
    @Published var outputDirectory: URL?

    let videoProcessor: VideoProcessor

    init() {
        // Set default output directory
        outputDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        // Create processor with configuration provider for per-job output URLs
        let defaultConfig = VideoConfiguration(
            outputURL: FileManager.default.temporaryDirectory.appendingPathComponent("temp.mp4")
        )

        let configProvider: VideoConfigurationProvider = { [weak self] jobId in
            guard let self = self, let dir = self.outputDirectory else { return nil }
            return VideoConfiguration(
                outputURL: dir.appendingPathComponent("\(jobId).mp4"),
                frameRate: self.frameRate,
                codec: self.codec,
                quality: self.quality
            )
        }

        videoProcessor = VideoProcessor(
            configuration: VideoProcessorConfiguration(
                autoAssemble: true,
                minimumFrames: 2,
                defaultVideoConfiguration: defaultConfig,
                configurationProvider: configProvider
            )
        )
    }

    func connect(to queue: JobQueue) {
        guard videoModeEnabled else { return }
        videoProcessor.connect(to: queue)
    }

    func disconnect() {
        videoProcessor.disconnect()
    }
}

struct ContentView: View {
    @StateObject private var queue = JobQueue()
    @StateObject private var videoSettings = VideoSettings()

    var body: some View {
        VStack {
            Toggle("Video Mode", isOn: $videoSettings.videoModeEnabled)

            if videoSettings.videoModeEnabled {
                // Configuration
                VideoConfigurationView(
                    frameRate: $videoSettings.frameRate,
                    codec: $videoSettings.codec,
                    quality: $videoSettings.quality,
                    interpolationEnabled: .constant(false),
                    interpolationFactor: .constant(2)
                )

                // Progress indicator
                VideoAssemblyProgressView(processor: videoSettings.videoProcessor)

                // Frame collection with removal support
                VideoFrameCollectionView(
                    frames: videoSettings.videoProcessor.collectedFrames,
                    thumbnailSize: 60
                ) { indices in
                    videoSettings.videoProcessor.removeFrames(at: indices)
                }
            }
        }
        .onChange(of: videoSettings.videoModeEnabled) { _, enabled in
            if enabled {
                videoSettings.connect(to: queue)
            } else {
                videoSettings.disconnect()
            }
        }
        .onReceive(videoSettings.videoProcessor.events) { event in
            if case .assemblyCompleted(_, let url) = event {
                #if os(macOS)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                #endif
            }
        }
    }
}
```

## Frame Interpolation

DrawThingsVideoKit includes frame interpolation using Core Image's dissolve transition. This creates smooth cross-fade effects between frames:

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    frameRate: 16,
    interpolation: .enabled(factor: 2)  // Doubles frame count
)
```

**Note:** This uses simple cross-fade blending, not motion-based interpolation. For advanced optical flow interpolation, consider integrating with external ML models.


## License

MIT License - see LICENSE file for details.
