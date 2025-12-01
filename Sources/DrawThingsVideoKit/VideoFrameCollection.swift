//
//  VideoFrameCollection.swift
//  DrawThingsVideoKit
//
//  Standardized container for video frames.
//

import Foundation
import CoreGraphics
import CoreImage

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

/// A standardized container for video frames that supports multiple image formats.
///
/// VideoFrameCollection provides a unified interface for working with sequences of images
/// regardless of their source format (CGImage, CIImage, platform images, or file URLs).
///
/// Example usage:
/// ```swift
/// // From URLs
/// let collection = VideoFrameCollection(urls: frameURLs)
///
/// // From CGImages
/// let collection = VideoFrameCollection(cgImages: images)
///
/// // Adding frames
/// var collection = VideoFrameCollection()
/// collection.append(cgImage: image)
/// collection.append(url: imageURL)
/// ```
public struct VideoFrameCollection: Sendable {
    /// The frames in this collection.
    public private(set) var frames: [VideoFrame]

    /// Metadata associated with this collection.
    public var metadata: VideoFrameMetadata

    /// The number of frames in the collection.
    public var count: Int { frames.count }

    /// Whether the collection is empty.
    public var isEmpty: Bool { frames.isEmpty }

    /// Creates an empty frame collection.
    public init() {
        self.frames = []
        self.metadata = VideoFrameMetadata()
    }

    /// Creates a frame collection from file URLs.
    ///
    /// - Parameters:
    ///   - urls: Array of image file URLs.
    ///   - metadata: Optional metadata for the collection.
    public init(urls: [URL], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = urls.map { VideoFrame.url($0) }
        self.metadata = metadata
    }

    /// Creates a frame collection from CGImages.
    ///
    /// - Parameters:
    ///   - cgImages: Array of CGImage instances.
    ///   - metadata: Optional metadata for the collection.
    public init(cgImages: [CGImage], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = cgImages.map { VideoFrame.cgImage($0) }
        self.metadata = metadata
    }

    /// Creates a frame collection from platform images.
    ///
    /// - Parameters:
    ///   - images: Array of platform-specific images (NSImage/UIImage).
    ///   - metadata: Optional metadata for the collection.
    public init(images: [PlatformImage], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = images.compactMap { image -> VideoFrame? in
            guard let cgImage = image.cgImage else { return nil }
            return .cgImage(cgImage)
        }
        self.metadata = metadata
    }

    // MARK: - Mutating Methods

    /// Appends a frame from a URL.
    public mutating func append(url: URL) {
        frames.append(.url(url))
    }

    /// Appends a frame from a CGImage.
    public mutating func append(cgImage: CGImage) {
        frames.append(.cgImage(cgImage))
    }

    /// Appends a frame from a platform image.
    public mutating func append(image: PlatformImage) {
        if let cgImage = image.cgImage {
            frames.append(.cgImage(cgImage))
        }
    }

    /// Appends all frames from another collection.
    public mutating func append(contentsOf other: VideoFrameCollection) {
        frames.append(contentsOf: other.frames)
    }

    /// Removes all frames from the collection.
    public mutating func removeAll() {
        frames.removeAll()
    }

    /// Removes frames at the specified indices.
    public mutating func remove(at indices: IndexSet) {
        frames.remove(atOffsets: indices)
    }

    // MARK: - Accessing Frames

    /// Accesses the frame at the specified index.
    public subscript(index: Int) -> VideoFrame {
        frames[index]
    }

    /// Returns the CGImage for the frame at the specified index.
    ///
    /// - Parameter index: The frame index.
    /// - Returns: The CGImage, or nil if it couldn't be loaded.
    public func cgImage(at index: Int) -> CGImage? {
        frames[index].cgImage
    }

    /// Returns all frames as CGImages.
    ///
    /// - Returns: Array of CGImages (frames that fail to load are excluded).
    public func allCGImages() -> [CGImage] {
        frames.compactMap { $0.cgImage }
    }
}

// MARK: - VideoFrame

/// A single frame in a video frame collection.
public enum VideoFrame: Sendable {
    /// A frame stored as a file URL.
    case url(URL)

    /// A frame stored as a CGImage.
    case cgImage(CGImage)

    /// Returns the CGImage representation of this frame.
    ///
    /// For URL frames, this loads the image from disk.
    public var cgImage: CGImage? {
        switch self {
        case .url(let url):
            return Self.loadCGImage(from: url)
        case .cgImage(let image):
            return image
        }
    }

    /// Loads a CGImage from a file URL.
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

// MARK: - VideoFrameMetadata

/// Metadata associated with a video frame collection.
public struct VideoFrameMetadata: Sendable {
    /// The source job ID if frames came from a DrawThingsKit job.
    public var sourceJobId: UUID?

    /// The prompt used to generate the frames.
    public var prompt: String?

    /// The negative prompt used to generate the frames.
    public var negativePrompt: String?

    /// The model used to generate the frames.
    public var model: String?

    /// The seed used for generation.
    public var seed: Int64?

    /// The timestamp when the frames were generated.
    public var generatedAt: Date?

    /// Custom metadata dictionary.
    public var custom: [String: String]

    /// Creates metadata with optional values.
    public init(
        sourceJobId: UUID? = nil,
        prompt: String? = nil,
        negativePrompt: String? = nil,
        model: String? = nil,
        seed: Int64? = nil,
        generatedAt: Date? = nil,
        custom: [String: String] = [:]
    ) {
        self.sourceJobId = sourceJobId
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.model = model
        self.seed = seed
        self.generatedAt = generatedAt
        self.custom = custom
    }
}

// MARK: - Collection Conformance

extension VideoFrameCollection: Collection {
    public var startIndex: Int { frames.startIndex }
    public var endIndex: Int { frames.endIndex }

    public func index(after i: Int) -> Int {
        frames.index(after: i)
    }
}

// MARK: - Platform Image Extension

#if canImport(AppKit)
extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif
