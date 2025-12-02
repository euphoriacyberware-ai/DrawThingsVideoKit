//
//  VideoFrameCollectionView.swift
//  DrawThingsVideoKit
//
//  SwiftUI view for displaying and managing collected video frames.
//

import SwiftUI
import CoreGraphics

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A SwiftUI view that displays collected video frames in a grid or list.
///
/// Features:
/// - Thumbnail grid of collected frames
/// - Frame count indicator
/// - Selection support for removing frames
/// - Reprocess button to re-encode with current settings
/// - Drag-and-drop reordering (macOS)
///
/// Example usage:
/// ```swift
/// @ObservedObject var processor: VideoProcessor
///
/// VideoFrameCollectionView(
///     frames: processor.collectedFrames,
///     onRemove: { indices in
///         // Handle frame removal
///     },
///     onReprocess: {
///         // Reprocess frames with current settings
///     }
/// )
/// ```
public struct VideoFrameCollectionView: View {
    let frames: VideoFrameCollection
    var onRemove: ((IndexSet) -> Void)?
    var onReprocess: (() -> Void)?
    var thumbnailSize: CGFloat
    var isReprocessing: Bool

    @State private var selectedIndices: Set<Int> = []

    public init(
        frames: VideoFrameCollection,
        thumbnailSize: CGFloat = 80,
        onRemove: ((IndexSet) -> Void)? = nil,
        onReprocess: (() -> Void)? = nil,
        isReprocessing: Bool = false
    ) {
        self.frames = frames
        self.thumbnailSize = thumbnailSize
        self.onRemove = onRemove
        self.onReprocess = onReprocess
        self.isReprocessing = isReprocessing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Frames")
                    .font(.headline)

                if !selectedIndices.isEmpty {
                    Button(role: .destructive) {
                        onRemove?(IndexSet(selectedIndices))
                        selectedIndices.removeAll()
                    } label: {
                        Label("Remove \(selectedIndices.count)", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        selectedIndices.removeAll()
                    } label: {
                        Text("Deselect")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                Spacer()

                // Reprocess button
                if let onReprocess = onReprocess, !frames.isEmpty {
                    Button {
                        onReprocess()
                    } label: {
                        if isReprocessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Reprocess", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isReprocessing)
                    .help("Re-encode video with current interpolation and upscaling settings")
                }

                Text("\(frames.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }

            if frames.isEmpty {
                emptyView
            } else {
                frameGrid
            }
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No frames collected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var frameGrid: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 4) {
                ForEach(0..<frames.count, id: \.self) { index in
                    FrameThumbnailView(
                        frame: frames[index],
                        size: thumbnailSize,
                        isSelected: selectedIndices.contains(index),
                        frameNumber: index + 1
                    )
                    .onTapGesture {
                        toggleSelection(index)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: thumbnailSize + 24)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func toggleSelection(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }
}

/// A single frame thumbnail view.
struct FrameThumbnailView: View {
    let frame: VideoFrame
    let size: CGFloat
    let isSelected: Bool
    let frameNumber: Int

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let cgImage = image {
                    #if canImport(AppKit)
                    Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                    #else
                    Image(uiImage: UIImage(cgImage: cgImage))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                    #endif
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }

                if isSelected {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: size, height: size)
                }
            }
            .cornerRadius(4)

            Text("\(frameNumber)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .task {
            // Load image asynchronously
            image = frame.cgImage
        }
    }
}

#Preview("With Frames") {
    // Create a mock frame collection with placeholder frames
    let collection = VideoFrameCollection()
    // Note: In real usage, these would be actual images

    return VStack {
        VideoFrameCollectionView(
            frames: collection,
            thumbnailSize: 60
        )
    }
    .padding()
    .frame(width: 400, height: 150)
}

#Preview("Empty") {
    VideoFrameCollectionView(
        frames: VideoFrameCollection(),
        thumbnailSize: 60
    )
    .padding()
    .frame(width: 400, height: 150)
}
