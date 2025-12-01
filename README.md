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
    frameRate: 24,
    codec: .h264,
    quality: .high,
    interpolation: .enabled(factor: 2)
)
```

**Properties:**
- `outputURL: URL` - Destination for the video file
- `frameRate: Int` - Target frame rate (default: 24)
- `codec: VideoCodec` - Video codec (.h264, .hevc, .proRes422, .proRes4444)
- `quality: VideoQuality` - Encoding quality (.low, .medium, .high, .maximum)
- `interpolation: InterpolationMode` - Frame interpolation (.disabled or .enabled(factor:))
- `overwriteExisting: Bool` - Whether to overwrite existing files (default: true)
- `audioURL: URL?` - Optional audio track

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

High-level coordinator that integrates with DrawThingsKit's JobQueue:

```swift
// Create processor
let processor = VideoProcessor(
    configuration: VideoProcessorConfiguration(
        autoAssemble: true,
        minimumFrames: 10,
        defaultVideoConfiguration: videoConfig
    )
)

// Subscribe to events
processor.events
    .sink { event in
        switch event {
        case .assemblyCompleted(_, let url):
            print("Video saved to: \(url)")
        case .assemblyFailed(_, let error):
            print("Assembly failed: \(error)")
        case .framesCollected(_, let count):
            print("Collected \(count) frames")
        default:
            break
        }
    }
    .store(in: &cancellables)

// Connect to DrawThingsKit job queue
await processor.connect(to: queue)
```

## UI Components

### VideoConfigurationView

SwiftUI view for configuring video output settings:

```swift
@State private var frameRate: Int = 24
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

### VideoAssemblyProgressView

Displays video assembly progress and status:

```swift
@ObservedObject var processor: VideoProcessor

VideoAssemblyProgressView(processor: processor) { outputURL in
    // Video is ready
    print("Video saved to: \(outputURL)")
}
```

### VideoFrameCollectionView

Displays collected frames with thumbnails:

```swift
VideoFrameCollectionView(
    frames: processor.collectedFrames,
    thumbnailSize: 80
) { indicesToRemove in
    // Handle frame removal
}
```

## Complete Example

```swift
import SwiftUI
import DrawThingsKit
import DrawThingsVideoKit
import Combine

struct VideoGenerationView: View {
    @StateObject private var queue = JobQueue()
    @StateObject private var processor: VideoProcessor
    @StateObject private var connectionManager = ConnectionManager()

    @State private var cancellables = Set<AnyCancellable>()

    init() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("output.mp4")

        let videoConfig = VideoConfiguration(
            outputURL: outputURL,
            frameRate: 24,
            interpolation: .disabled
        )

        _processor = StateObject(wrappedValue: VideoProcessor(
            configuration: VideoProcessorConfiguration(
                autoAssemble: false,
                minimumFrames: 10,
                defaultVideoConfiguration: videoConfig,
                collectAllCompletedJobs: true
            )
        ))
    }

    var body: some View {
        VStack {
            // Frame collection display
            VideoFrameCollectionView(frames: processor.collectedFrames)

            // Assembly progress
            VideoAssemblyProgressView(processor: processor)

            // Assemble button
            Button("Assemble Video") {
                Task {
                    try await processor.assembleCollectedFrames()
                }
            }
            .disabled(processor.collectedFrames.isEmpty || processor.isAssembling)
        }
        .task {
            // Connect processor to job queue
            processor.connect(to: queue)
        }
    }
}
```

## Frame Interpolation

DrawThingsVideoKit includes frame interpolation using Core Image's dissolve transition. This creates smooth cross-fade effects between frames:

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    frameRate: 24,
    interpolation: .enabled(factor: 2)  // Doubles frame count
)
```

**Note:** This uses simple cross-fade blending, not motion-based interpolation. For advanced optical flow interpolation, consider integrating with external ML models.

## License

MIT License - see LICENSE file for details.
