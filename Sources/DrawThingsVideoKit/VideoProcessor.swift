//
//  VideoProcessor.swift
//  DrawThingsVideoKit
//
//  Coordinator that subscribes to JobQueue events for automatic video assembly.
//

import Foundation
import Combine
import DrawThingsKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Events emitted by the VideoProcessor.
public enum VideoProcessorEvent: Sendable {
    /// Video assembly started
    case assemblyStarted(jobId: UUID)

    /// Video assembly progress updated
    case assemblyProgress(jobId: UUID, progress: Double)

    /// Video assembly completed successfully
    case assemblyCompleted(jobId: UUID, outputURL: URL)

    /// Video assembly failed with error
    case assemblyFailed(jobId: UUID, error: Error)

    /// Frames were collected from a job
    case framesCollected(jobId: UUID, count: Int)
}

/// A closure that generates a VideoConfiguration for a given job ID.
/// This allows dynamic output URLs based on job ID.
public typealias VideoConfigurationProvider = @Sendable (UUID) -> VideoConfiguration?

/// Configuration for automatic video assembly from queue jobs.
public struct VideoProcessorConfiguration: @unchecked Sendable {
    /// Whether to automatically assemble videos when jobs complete.
    public var autoAssemble: Bool

    /// Minimum number of frames required before auto-assembly triggers.
    public var minimumFrames: Int

    /// Default video configuration to use for auto-assembly.
    /// Used when `configurationProvider` is nil or returns nil.
    public var defaultVideoConfiguration: VideoConfiguration

    /// Whether to collect frames from all completed jobs or just marked video jobs.
    public var collectAllCompletedJobs: Bool

    /// Whether to clear collected frames after successful auto-assembly.
    /// Set to `false` to retain frames for reprocessing with different settings.
    public var clearFramesAfterAssembly: Bool

    /// Optional provider for dynamic video configuration per job.
    /// When set, this is called with the job ID to generate a configuration
    /// with a unique output URL (e.g., `{outputDir}/{jobId}.mp4`).
    public var configurationProvider: VideoConfigurationProvider?

    /// Creates a new processor configuration.
    public init(
        autoAssemble: Bool = false,
        minimumFrames: Int = 2,
        defaultVideoConfiguration: VideoConfiguration,
        collectAllCompletedJobs: Bool = false,
        clearFramesAfterAssembly: Bool = true,
        configurationProvider: VideoConfigurationProvider? = nil
    ) {
        self.autoAssemble = autoAssemble
        self.minimumFrames = minimumFrames
        self.defaultVideoConfiguration = defaultVideoConfiguration
        self.collectAllCompletedJobs = collectAllCompletedJobs
        self.clearFramesAfterAssembly = clearFramesAfterAssembly
        self.configurationProvider = configurationProvider
    }
}

/// Coordinates video assembly from DrawThingsKit job queue events.
///
/// VideoProcessor can operate in two modes:
/// 1. **Automatic mode**: Subscribes to JobQueue events and automatically
///    collects frames from completed jobs, assembling them into video when
///    certain conditions are met.
/// 2. **Manual mode**: Provides methods for manually assembling videos from
///    any collection of frames.
///
/// Example usage:
/// ```swift
/// // Create processor with a default output configuration
/// let outputURL = FileManager.default.temporaryDirectory
///     .appendingPathComponent("output.mp4")
/// let videoConfig = VideoConfiguration(outputURL: outputURL)
///
/// let processor = VideoProcessor(
///     configuration: VideoProcessorConfiguration(
///         autoAssemble: true,
///         minimumFrames: 10,
///         defaultVideoConfiguration: videoConfig
///     )
/// )
///
/// // Subscribe to events
/// processor.events
///     .sink { event in
///         switch event {
///         case .assemblyCompleted(_, let url):
///             print("Video saved to: \(url)")
///         case .assemblyFailed(_, let error):
///             print("Assembly failed: \(error)")
///         default:
///             break
///         }
///     }
///     .store(in: &cancellables)
///
/// // Connect to job queue (on MainActor)
/// await processor.connect(to: queue)
/// ```
@MainActor
public final class VideoProcessor: ObservableObject {
    // MARK: - Published Properties

    /// Current collection of frames from completed jobs.
    @Published public private(set) var collectedFrames: VideoFrameCollection

    /// Whether video assembly is currently in progress.
    @Published public private(set) var isAssembling: Bool = false

    /// Current assembly progress (0.0 to 1.0).
    @Published public private(set) var assemblyProgress: Double = 0

    /// Last error that occurred during assembly.
    @Published public private(set) var lastError: Error?

    // MARK: - Event Publisher

    /// Publisher for video processor events.
    public let events = PassthroughSubject<VideoProcessorEvent, Never>()

    // MARK: - Private Properties

    private var configuration: VideoProcessorConfiguration
    private let assembler: VideoAssembler
    private var cancellables = Set<AnyCancellable>()
    private var assemblyTask: Task<Void, Never>?
    private var currentJobId: UUID?

    // MARK: - Initialization

    /// Creates a new video processor.
    ///
    /// - Parameter configuration: Configuration for automatic assembly.
    public init(configuration: VideoProcessorConfiguration) {
        self.configuration = configuration
        self.assembler = VideoAssembler()
        self.collectedFrames = VideoFrameCollection()
    }

    // MARK: - Queue Connection

    /// Connect to a JobQueue to receive completion events.
    ///
    /// - Parameter queue: The JobQueue to subscribe to.
    public func connect(to queue: JobQueue) {
        // Disconnect any existing subscription
        disconnect()

        queue.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleJobEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    /// Disconnect from the current job queue.
    public func disconnect() {
        cancellables.removeAll()
    }

    // MARK: - Frame Collection

    /// Add frames from a completed job.
    ///
    /// - Parameters:
    ///   - images: The images from the completed job.
    ///   - job: The source job for metadata.
    public func addFrames(from images: [PlatformImage], job: GenerationJob) {
        let cgImages = images.compactMap { $0.cgImage }
        guard !cgImages.isEmpty else { return }

        // If this is a new job (different from the previous one), clear existing frames
        // This prevents frames from multiple video generations being mixed together
        if let existingJobId = collectedFrames.metadata.sourceJobId, existingJobId != job.id {
            clearFrames()
        }

        // Create metadata from job
        var metadata = collectedFrames.metadata
        if metadata.sourceJobId == nil {
            metadata.sourceJobId = job.id
        }
        metadata.prompt = job.prompt
        metadata.negativePrompt = job.negativePrompt
        if let config = try? job.configuration() {
            metadata.model = config.model
            metadata.seed = config.seed
        }
        metadata.generatedAt = job.completedAt ?? Date()

        // Add frames
        for cgImage in cgImages {
            collectedFrames.append(cgImage: cgImage)
        }
        collectedFrames.metadata = metadata

        events.send(.framesCollected(jobId: job.id, count: cgImages.count))

        // Check for auto-assembly
        if configuration.autoAssemble && collectedFrames.count >= configuration.minimumFrames {
            Task {
                await triggerAutoAssembly(forJobId: job.id)
            }
        }
    }

    /// Add frames from URLs.
    ///
    /// - Parameter urls: URLs of image files to add.
    public func addFrames(from urls: [URL]) {
        for url in urls {
            collectedFrames.append(url: url)
        }
    }

    /// Add frames from a VideoFrameCollection.
    ///
    /// - Parameter collection: The frame collection to add.
    public func addFrames(from collection: VideoFrameCollection) {
        collectedFrames.append(contentsOf: collection)
    }

    /// Clear all collected frames.
    public func clearFrames() {
        collectedFrames.removeAll()
    }

    /// Remove frames at the specified indices.
    ///
    /// - Parameter indices: The indices of frames to remove.
    public func removeFrames(at indices: IndexSet) {
        collectedFrames.remove(at: indices)
    }

    /// Replace all collected frames with a new collection.
    ///
    /// - Parameter collection: The new frame collection.
    public func replaceFrames(with collection: VideoFrameCollection) {
        collectedFrames = collection
    }

    // MARK: - Manual Assembly

    /// Assemble collected frames into a video.
    ///
    /// - Parameter configuration: Optional configuration override.
    /// - Returns: The URL of the assembled video.
    /// - Throws: VideoAssemblerError if assembly fails.
    @discardableResult
    public func assembleCollectedFrames(
        configuration: VideoConfiguration? = nil
    ) async throws -> URL {
        let config = configuration ?? self.configuration.defaultVideoConfiguration
        return try await assemble(frames: collectedFrames, configuration: config)
    }

    /// Assemble arbitrary frames into a video.
    ///
    /// - Parameters:
    ///   - frames: The frame collection to assemble.
    ///   - configuration: Video output configuration.
    /// - Returns: The URL of the assembled video.
    /// - Throws: VideoAssemblerError if assembly fails.
    @discardableResult
    public func assemble(
        frames: VideoFrameCollection,
        configuration: VideoConfiguration
    ) async throws -> URL {
        let jobId = frames.metadata.sourceJobId ?? UUID()

        isAssembling = true
        assemblyProgress = 0
        lastError = nil
        currentJobId = jobId

        events.send(.assemblyStarted(jobId: jobId))

        do {
            let outputURL = try await assembler.assemble(
                frames: frames,
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.assemblyProgress = progress
                    self?.events.send(.assemblyProgress(jobId: jobId, progress: progress))
                }
            }

            isAssembling = false
            assemblyProgress = 1.0
            currentJobId = nil

            events.send(.assemblyCompleted(jobId: jobId, outputURL: outputURL))

            return outputURL
        } catch {
            isAssembling = false
            lastError = error
            currentJobId = nil

            events.send(.assemblyFailed(jobId: jobId, error: error))

            throw error
        }
    }

    /// Assemble frames from image URLs.
    ///
    /// - Parameters:
    ///   - urls: URLs of image files.
    ///   - configuration: Video output configuration.
    /// - Returns: The URL of the assembled video.
    /// - Throws: VideoAssemblerError if assembly fails.
    @discardableResult
    public func assemble(
        urls: [URL],
        configuration: VideoConfiguration
    ) async throws -> URL {
        let collection = VideoFrameCollection(urls: urls)
        return try await assemble(frames: collection, configuration: configuration)
    }

    // MARK: - Configuration

    /// Update the processor configuration.
    ///
    /// - Parameter configuration: New configuration.
    public func updateConfiguration(_ configuration: VideoProcessorConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Private Methods

    /// Handle job queue events.
    private func handleJobEvent(_ event: JobEvent) {
        switch event {
        case .jobCompleted(let job, let images):
            if configuration.collectAllCompletedJobs || isVideoJob(job) {
                addFrames(from: images, job: job)
            }
        default:
            break
        }
    }

    /// Check if a job is marked as a video generation job.
    private func isVideoJob(_ job: GenerationJob) -> Bool {
        // Check configuration for video-related settings
        guard let config = try? job.configuration() else { return false }
        return config.numFrames > 1
    }

    /// Trigger automatic assembly.
    private func triggerAutoAssembly(forJobId jobId: UUID) async {
        guard !isAssembling else { return }

        // Get configuration from provider or use default
        let videoConfig: VideoConfiguration
        if let provider = configuration.configurationProvider,
           let config = provider(jobId) {
            videoConfig = config
        } else {
            videoConfig = configuration.defaultVideoConfiguration
        }

        do {
            try await assemble(frames: collectedFrames, configuration: videoConfig)
            // Clear frames after successful assembly (if configured)
            if configuration.clearFramesAfterAssembly {
                clearFrames()
            }
        } catch {
            // Error is already published via events
        }
    }
}

