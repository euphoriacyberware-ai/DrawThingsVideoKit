//
//  VideoFrameCollectionView.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

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
    var onSave: ((URL) async throws -> Void)?
    var onLoad: ((URL) async throws -> VideoFrameCollection)?
    var thumbnailSize: CGFloat
    var isReprocessing: Bool

    @State private var selectedIndices: Set<Int> = []
    @State private var showingSavePanel: Bool = false
    @State private var showingLoadPanel: Bool = false
    @State private var isSaving: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    public init(
        frames: VideoFrameCollection,
        thumbnailSize: CGFloat = 80,
        onRemove: ((IndexSet) -> Void)? = nil,
        onReprocess: (() -> Void)? = nil,
        onSave: ((URL) async throws -> Void)? = nil,
        onLoad: ((URL) async throws -> VideoFrameCollection)? = nil,
        isReprocessing: Bool = false
    ) {
        self.frames = frames
        self.thumbnailSize = thumbnailSize
        self.onRemove = onRemove
        self.onReprocess = onReprocess
        self.onSave = onSave
        self.onLoad = onLoad
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

            // Save/Load buttons
            if onSave != nil || onLoad != nil {
                saveLoadButtons
            }

            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .fileImporter(
            isPresented: $showingLoadPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleLoadResult(result)
        }
        .fileExporter(
            isPresented: $showingSavePanel,
            document: FrameCollectionDocument(),
            contentType: .folder,
            defaultFilename: "VideoFrames"
        ) { result in
            handleSaveResult(result)
        }
    }

    // MARK: - Save/Load Buttons

    private var saveLoadButtons: some View {
        HStack(spacing: 8) {
            if let _ = onLoad {
                Button {
                    #if os(macOS)
                    openLoadPanel()
                    #else
                    showingLoadPanel = true
                    #endif
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Load Frames", systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || isSaving)
                .help("Load frames from a saved collection")
            }

            if let _ = onSave, !frames.isEmpty {
                Button {
                    #if os(macOS)
                    openSavePanel()
                    #else
                    showingSavePanel = true
                    #endif
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save Frames", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || isSaving)
                .help("Save frames to disk for later use")
            }

            Spacer()
        }
    }

    // MARK: - macOS Panel Helpers

    #if os(macOS)
    private func openLoadPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing saved video frames"
        panel.prompt = "Load"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                handleLoadResult(.success([url]))
            }
        }
    }

    private func openSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "VideoFrames"
        panel.message = "Choose where to save video frames"
        panel.prompt = "Save"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                handleSaveResult(.success(url))
            }
        }
    }
    #endif

    // MARK: - File Handling

    private func handleSaveResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard let onSave = onSave else { return }
            isSaving = true
            errorMessage = nil
            Task {
                do {
                    try await onSave(url)
                    await MainActor.run {
                        isSaving = false
                    }
                } catch {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = "Save failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleLoadResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let onLoad = onLoad else { return }
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    _ = try await onLoad(url)
                    await MainActor.run {
                        isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "Load failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = "Load failed: \(error.localizedDescription)"
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

// MARK: - File Document for Export

/// A placeholder document for the file exporter to create a folder.
/// The actual saving is handled by the onSave callback.
struct FrameCollectionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    init() {}

    init(configuration: ReadConfiguration) throws {
        // Not used for reading
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Return an empty directory wrapper - actual content is written by onSave
        return FileWrapper(directoryWithFileWrappers: [:])
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
