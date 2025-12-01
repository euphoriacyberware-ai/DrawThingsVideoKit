//
//  DrawThingsVideoKit.swift
//  DrawThingsVideoKit
//
//  Public API for video assembly from DrawThingsKit.
//
//  DrawThingsVideoKit extends DrawThingsKit with video assembly capabilities,
//  allowing you to create videos from generated image sequences.
//
//  Key Components:
//  - VideoConfiguration: Settings for video output (codec, quality, frame rate)
//  - VideoFrameCollection: Standardized container for video frames
//  - VideoAssembler: Low-level frame-to-video assembly
//  - VideoProcessor: High-level coordinator with JobQueue integration
//
//  Example usage:
//  ```swift
//  import DrawThingsKit
//  import DrawThingsVideoKit
//
//  // Create a video processor
//  let outputURL = FileManager.default.temporaryDirectory
//      .appendingPathComponent("output.mp4")
//
//  let videoConfig = VideoConfiguration(
//      outputURL: outputURL,
//      frameRate: 24,
//      interpolation: .enabled(factor: 2)
//  )
//
//  let processor = VideoProcessor(
//      configuration: VideoProcessorConfiguration(
//          autoAssemble: true,
//          minimumFrames: 10,
//          defaultVideoConfiguration: videoConfig
//      )
//  )
//
//  // Connect to job queue for automatic assembly
//  processor.connect(to: queue)
//
//  // Or manually assemble frames
//  let frames = VideoFrameCollection(urls: imageURLs)
//  let outputURL = try await processor.assemble(
//      frames: frames,
//      configuration: videoConfig
//  )
//  ```
//

import Foundation

// Re-export all public types
@_exported import struct Foundation.URL
@_exported import struct Foundation.UUID

// Version information
public enum DrawThingsVideoKitInfo {
    public static let version = "1.0.0"
    public static let minimumPlatformVersion = "macOS 14.0 / iOS 17.0"
}
