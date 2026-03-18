//
//  VideoAssemblyProgressView.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import SwiftUI

/// A SwiftUI view that displays video assembly progress.
///
/// Shows:
/// - Progress bar during assembly
/// - Current stage (interpolation vs encoding)
/// - Completion status with output file info
///
/// Example usage:
/// ```swift
/// @ObservedObject var processor: VideoProcessor
///
/// VideoAssemblyProgressView(processor: processor)
/// ```
public struct VideoAssemblyProgressView: View {
    @ObservedObject var processor: VideoProcessor

    /// Optional completion handler for when video is ready.
    public var onVideoReady: ((URL) -> Void)?

    /// The last completed video URL.
    @State private var completedVideoURL: URL?

    public init(
        processor: VideoProcessor,
        onVideoReady: ((URL) -> Void)? = nil
    ) {
        self.processor = processor
        self.onVideoReady = onVideoReady
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if processor.isAssembling {
                assemblingView
            } else if let error = processor.lastError {
                errorView(error)
            } else if let url = completedVideoURL {
                completedView(url)
            } else if !processor.collectedFrames.isEmpty {
                readyView
            } else {
                emptyView
            }
        }
        .onReceive(processor.events) { event in
            if case .assemblyCompleted(_, let url) = event {
                completedVideoURL = url
                onVideoReady?(url)
            }
        }
    }

    // MARK: - Subviews

    private var assemblingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Assembling video...")
                    .font(.headline)
            }

            ProgressView(value: processor.assemblyProgress) {
                Text(progressLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
        }
    }

    private var progressLabel: String {
        let percentage = Int(processor.assemblyProgress * 100)
        if processor.assemblyProgress < 0.5 {
            return "Interpolating frames... \(percentage)%"
        } else {
            return "Encoding video... \(percentage)%"
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Assembly Failed")
                    .font(.headline)
            }

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func completedView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Video Ready")
                    .font(.headline)
            }

            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)

            #if os(macOS)
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
            .buttonStyle(.bordered)
            #endif
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundColor(.blue)
                Text("\(processor.collectedFrames.count) Frames Ready")
                    .font(.headline)
            }

            Text("Ready to assemble into video")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(.secondary)
                Text("No Frames")
                    .font(.headline)
            }

            Text("Generate images to collect frames for video")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview("Empty") {
    let config = VideoProcessorConfiguration(
        defaultVideoConfiguration: VideoConfiguration(
            outputURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )
    )
    let processor = VideoProcessor(configuration: config)

    return VideoAssemblyProgressView(processor: processor)
        .padding()
        .frame(width: 300)
}
