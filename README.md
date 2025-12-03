# DrawThingsVideoKit

A Swift package that extends [DrawThingsKit](https://github.com/euphoriacyberware-ai/DrawThingsKit) with video assembly capabilities, allowing you to create videos from generated image sequences.

## Requirements

- macOS 14.0+ / iOS 17.0+
- Swift 5.9+
- Xcode 15.0+

### Optional ML Features

- **ML Frame Interpolation**: macOS 15.4+ / iOS 18.4+ (VTFrameProcessor)
- **ML Super Resolution**: macOS 26+ / iOS 26+ (VTSuperResolutionScaler)

Fallback implementations using Core Image are available on older systems.

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

Settings for video output including codec, quality, frame rate, interpolation, and super resolution:

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    frameRate: 24,  // Target output frame rate
    codec: .h264,
    quality: .high,
    interpolation: .enabled(factor: 2),
    superResolution: .enabled(factor: 2)
)
```

**Properties:**
- `outputURL: URL` - Destination for the video file
- `sourceFrameRate: Int` - Source frame rate of input frames (default: 16, matching Draw Things output)
- `frameRate: Int` - Target output frame rate when interpolation is enabled (default: 24)
- `codec: VideoCodec` - Video codec (.h264, .hevc, .proRes422, .proRes4444)
- `quality: VideoQuality` - Encoding quality (.low, .medium, .high, .maximum)
- `interpolation: InterpolationMode` - Frame interpolation (.disabled or .enabled(factor:))
- `interpolationMethod: InterpolationMethod?` - Preferred method (.vtFrameProcessor or .coreImageDissolve)
- `superResolution: SuperResolutionMode` - Upscaling (.disabled or .enabled(factor:))
- `superResolutionMethod: SuperResolutionMethod?` - Preferred method (.vtSuperResolution, .vtLowLatency, or .coreImageLanczos)
- `overwriteExisting: Bool` - Whether to overwrite existing files (default: true)
- `audioURL: URL?` - Optional audio track (planned for future release)

**Note:** When interpolation is disabled, `sourceFrameRate` is used for encoding to maintain correct video duration. When interpolation is enabled, `frameRate` determines the output playback rate.

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

Low-level frame-to-video assembly using AVFoundation with optional frame interpolation and super resolution:

```swift
let assembler = VideoAssembler(
    preferredInterpolationMethod: .vtFrameProcessor,
    preferredSuperResolutionMethod: .vtSuperResolution
)

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
        frameRate: 24,
        codec: .h264,
        quality: .high,
        interpolation: .enabled(factor: 2),
        superResolution: .enabled(factor: 2)
    )
}

// Create processor with auto-assembly enabled
let processor = VideoProcessor(
    configuration: VideoProcessorConfiguration(
        autoAssemble: true,
        minimumFrames: 2,
        defaultVideoConfiguration: defaultConfig,
        collectAllCompletedJobs: false,  // Only collect video jobs (numFrames > 1)
        clearFramesAfterAssembly: false, // Retain frames for reprocessing
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
@State private var frameRate: Int = 24
@State private var codec: VideoCodec = .h264
@State private var quality: VideoQuality = .high
@State private var interpolationEnabled: Bool = false
@State private var interpolationFactor: Int = 2
@State private var interpolationMethod: InterpolationMethod? = nil
@State private var superResolutionEnabled: Bool = false
@State private var superResolutionFactor: Int = 2
@State private var superResolutionMethod: SuperResolutionMethod? = nil

VideoConfigurationView(
    frameRate: $frameRate,
    codec: $codec,
    quality: $quality,
    interpolationEnabled: $interpolationEnabled,
    interpolationFactor: $interpolationFactor,
    interpolationMethod: $interpolationMethod,
    superResolutionEnabled: $superResolutionEnabled,
    superResolutionFactor: $superResolutionFactor,
    superResolutionMethod: $superResolutionMethod,
    frameDimensions: CGSize(width: 704, height: 384)  // Optional: shows output dimensions
)
```

Provides controls for:
- Video codec (H.264, HEVC, ProRes 422, ProRes 4444)
- Quality preset (Low, Medium, High, Maximum)
- Frame interpolation with target frame rate presets:
  - 24 fps - Cinematic
  - 25 fps - PAL
  - 30 fps - NTSC
  - 48 fps - High Frame Rate
  - 60 fps - High Motion
- Interpolation method selection (Auto, ML-based, Cross Dissolve)
- Super resolution upscaling (2x, 3x, 4x)
- Super resolution method selection (Auto, ML Super Resolution, ML Low Latency, Lanczos)
- ML model download status and button

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
- Stage indicator (interpolating, upscaling, or encoding)
- Completion status with "Show in Finder" button (macOS)
- Error display on failure
- Frame count when ready to assemble

### VideoFrameCollectionView

Displays collected frames with thumbnails, selection, and reprocessing support:

```swift
VideoFrameCollectionView(
    frames: processor.collectedFrames,
    thumbnailSize: 80,
    onRemove: { indicesToRemove in
        processor.removeFrames(at: indicesToRemove)
    },
    onReprocess: {
        // Re-encode with current interpolation/upscaling settings
        reprocessFrames()
    },
    isReprocessing: isReprocessing
)
```

Features:
- Horizontal scrolling thumbnail grid
- Frame count indicator
- Tap to select/deselect frames
- "Remove N" button appears when frames are selected
- "Deselect" button to clear selection
- "Reprocess" button to re-encode video with different settings

## Frame Interpolation

DrawThingsVideoKit supports frame interpolation to increase output frame rate for smoother video playback. Draw Things generates video at 16 FPS (model limitation), and interpolation can increase this to higher frame rates.

### Target Frame Rate Presets

The UI provides frame rate presets based on source 16 FPS. Interpolation uses integer factors (2x, 3x, 4x), which affects duration:

| Target | Factor | Duration Effect | Use Case |
|--------|--------|-----------------|----------|
| 24 fps | 2x | ~33% slower | Cinematic film look |
| 30 fps | 2x | ~6% slower | Broadcast standard |
| 32 fps | 2x | Same duration | Smooth playback |
| 48 fps | 3x | Same duration | High frame rate |
| 64 fps | 4x | Same duration | Ultra smooth |

**Duration math:** With 2x interpolation, 81 source frames become ~161 frames. At 32 fps (16×2), duration stays the same. At 24 fps, the video plays slower because the same frames are displayed at a lower rate.

### Interpolation Methods

**ML Frame Interpolation** (macOS 15.4+, iOS 18.4+)
- Uses Apple's VTFrameProcessor with neural network-based motion estimation
- Provides motion-aware interpolation for natural-looking results
- Handles complex motion better than simple blending

**Cross Dissolve** (All platforms)
- Uses Core Image's CIDissolveTransition filter
- Creates cross-fade blended intermediate frames
- Works well for slow, gradual movements typical of diffusion model outputs
- Fast motion may show ghosting artifacts

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    sourceFrameRate: 16,  // Draw Things default
    frameRate: 24,
    interpolation: .enabled(factor: 2),
    interpolationMethod: .vtFrameProcessor  // or .coreImageDissolve, or nil for auto
)
```

## Super Resolution

DrawThingsVideoKit includes ML-based super resolution to upscale video output to higher resolutions.

### Methods

**ML Super Resolution** (macOS 26+, iOS 26+)
- Uses Apple's VTSuperResolutionScaler
- Neural network-based upscaling with detail enhancement
- Maximum input: 1920x1080 for video, 1920x1920 for images
- Requires one-time model download (~100-200 MB per scale factor)

**ML Low Latency** (macOS 26+, iOS 26+)
- Uses VTLowLatencySuperResolutionScaler
- Faster processing with slightly less detail enhancement
- Better for real-time or batch processing

**Lanczos Scale** (All platforms)
- Uses Core Image's Lanczos resampling
- High-quality traditional upscaling
- Works with any input size
- No model download required

```swift
let config = VideoConfiguration(
    outputURL: outputURL,
    superResolution: .enabled(factor: 2),
    superResolutionMethod: .vtSuperResolution  // or .vtLowLatency, .coreImageLanczos, or nil for auto
)
```

### Model Downloads

ML super resolution requires downloading models from Apple. The UI shows model status and provides a download button:

```swift
// Check model status
let status = SuperResolutionScaler.modelStatus(
    forWidth: 704,
    height: 384,
    scaleFactor: 2
)

switch status {
case .ready:
    print("Models available")
case .downloadRequired:
    print("Download needed")
case .downloading(let progress):
    print("Downloading: \(Int(progress * 100))%")
case .notApplicable:
    print("VT not available, using Core Image")
}

// Download models
try await SuperResolutionScaler.downloadModels(
    forWidth: 704,
    height: 384,
    scaleFactor: 2
) { progress in
    print("Download progress: \(Int(progress * 100))%")
}
```

## Reprocessing

When `clearFramesAfterAssembly` is set to `false`, frames are retained after video assembly. This enables reprocessing the same frames with different settings:

```swift
// Configure processor to retain frames
let config = VideoProcessorConfiguration(
    autoAssemble: true,
    clearFramesAfterAssembly: false,  // Keep frames after assembly
    ...
)

// After initial assembly, change settings and reprocess
videoSettings.interpolationEnabled = true
videoSettings.superResolutionEnabled = true

// Create new assembler with updated settings
let assembler = VideoAssembler(
    preferredInterpolationMethod: videoSettings.interpolationMethod,
    preferredSuperResolutionMethod: videoSettings.superResolutionMethod
)

let newConfig = VideoConfiguration(
    outputURL: newOutputURL,
    frameRate: 24,
    interpolation: .enabled(factor: 2),
    superResolution: .enabled(factor: 2)
)

let result = try await assembler.assemble(
    frames: processor.collectedFrames,
    configuration: newConfig
)
```

This workflow is ideal for:
- Testing different interpolation/upscaling settings without regenerating
- Creating multiple output versions (e.g., 1080p and 4K)
- Experimenting with codec and quality settings

## Complete Example

```swift
import SwiftUI
import DrawThingsKit
import DrawThingsVideoKit
import Combine

@MainActor
class VideoSettings: ObservableObject {
    @Published var videoModeEnabled = false
    @Published var frameRate: Int = 24
    @Published var codec: VideoCodec = .h264
    @Published var quality: VideoQuality = .high
    @Published var interpolationEnabled: Bool = false
    @Published var interpolationFactor: Int = 2
    @Published var interpolationMethod: InterpolationMethod? = nil
    @Published var superResolutionEnabled: Bool = false
    @Published var superResolutionFactor: Int = 2
    @Published var superResolutionMethod: SuperResolutionMethod? = nil
    @Published var outputDirectory: URL?
    @Published var isReprocessing: Bool = false

    private(set) var videoProcessor: VideoProcessor!
    private var cancellables = Set<AnyCancellable>()

    var collectedFrames: VideoFrameCollection {
        videoProcessor?.collectedFrames ?? VideoFrameCollection()
    }

    var frameDimensions: CGSize? {
        guard let firstFrame = collectedFrames.first,
              let cgImage = firstFrame.cgImage else { return nil }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    init() {
        outputDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        setupVideoProcessor()

        // Forward objectWillChange for SwiftUI updates
        videoProcessor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func setupVideoProcessor() {
        let defaultConfig = VideoConfiguration(
            outputURL: FileManager.default.temporaryDirectory.appendingPathComponent("temp.mp4")
        )

        let configProvider: VideoConfigurationProvider = { [weak self] jobId in
            guard let self = self, let dir = self.outputDirectory else { return nil }
            return VideoConfiguration(
                outputURL: dir.appendingPathComponent("\(jobId).mp4"),
                frameRate: self.frameRate,
                codec: self.codec,
                quality: self.quality,
                interpolation: self.interpolationEnabled ? .enabled(factor: self.interpolationFactor) : .disabled,
                superResolution: self.superResolutionEnabled ? .enabled(factor: self.superResolutionFactor) : .disabled
            )
        }

        videoProcessor = VideoProcessor(
            configuration: VideoProcessorConfiguration(
                autoAssemble: true,
                minimumFrames: 2,
                defaultVideoConfiguration: defaultConfig,
                collectAllCompletedJobs: false,
                clearFramesAfterAssembly: false,
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

    func reprocessFrames() {
        guard !collectedFrames.isEmpty, let outputDir = outputDirectory else { return }
        isReprocessing = true

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        var suffix = ""
        if interpolationEnabled { suffix += "_\(interpolationFactor)x-interp" }
        if superResolutionEnabled { suffix += "_\(superResolutionFactor)x-upscale" }
        if suffix.isEmpty { suffix = "_reprocess" }

        let outputURL = outputDir.appendingPathComponent("video_\(timestamp)\(suffix).mp4")

        let config = VideoConfiguration(
            outputURL: outputURL,
            frameRate: frameRate,
            codec: codec,
            quality: quality,
            interpolation: interpolationEnabled ? .enabled(factor: interpolationFactor) : .disabled,
            interpolationMethod: interpolationMethod,
            superResolution: superResolutionEnabled ? .enabled(factor: superResolutionFactor) : .disabled,
            superResolutionMethod: superResolutionMethod
        )

        Task {
            do {
                let assembler = VideoAssembler(
                    preferredInterpolationMethod: interpolationMethod,
                    preferredSuperResolutionMethod: superResolutionMethod
                )
                _ = try await assembler.assemble(frames: collectedFrames, configuration: config)
                await MainActor.run { isReprocessing = false }
            } catch {
                await MainActor.run { isReprocessing = false }
                print("Reprocess failed: \(error)")
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var queue = JobQueue()
    @StateObject private var videoSettings = VideoSettings()

    var body: some View {
        VStack {
            Toggle("Video Mode", isOn: $videoSettings.videoModeEnabled)

            if videoSettings.videoModeEnabled {
                VideoConfigurationView(
                    frameRate: $videoSettings.frameRate,
                    codec: $videoSettings.codec,
                    quality: $videoSettings.quality,
                    interpolationEnabled: $videoSettings.interpolationEnabled,
                    interpolationFactor: $videoSettings.interpolationFactor,
                    interpolationMethod: $videoSettings.interpolationMethod,
                    superResolutionEnabled: $videoSettings.superResolutionEnabled,
                    superResolutionFactor: $videoSettings.superResolutionFactor,
                    superResolutionMethod: $videoSettings.superResolutionMethod,
                    frameDimensions: videoSettings.frameDimensions
                )

                VideoAssemblyProgressView(processor: videoSettings.videoProcessor)

                if !videoSettings.collectedFrames.isEmpty {
                    VideoFrameCollectionView(
                        frames: videoSettings.collectedFrames,
                        thumbnailSize: 60,
                        onRemove: { indices in
                            videoSettings.videoProcessor.removeFrames(at: indices)
                        },
                        onReprocess: {
                            videoSettings.reprocessFrames()
                        },
                        isReprocessing: videoSettings.isReprocessing
                    )
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
    }
}
```

## App Sandbox Entitlements

For macOS apps using App Sandbox, you'll need the following entitlements to save videos to user-selected directories:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

## License

MIT License - see LICENSE file for details.
