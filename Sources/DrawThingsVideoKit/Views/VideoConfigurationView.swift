//
//  VideoConfigurationView.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import SwiftUI

/// A SwiftUI view for configuring video assembly settings.
///
/// Provides controls for:
/// - Output frame rate
/// - Video codec selection
/// - Quality preset
/// - Frame interpolation settings
/// - Super resolution upscaling settings
///
/// Example usage:
/// ```swift
/// @State private var frameRate: Int = 24
/// @State private var codec: VideoCodec = .h264
/// @State private var quality: VideoQuality = .high
/// @State private var interpolationEnabled: Bool = false
/// @State private var interpolationFactor: Int = 2
/// @State private var interpolationMethod: InterpolationMethod? = nil
/// @State private var superResolutionEnabled: Bool = false
/// @State private var superResolutionFactor: Int = 2
/// @State private var superResolutionMethod: SuperResolutionMethod? = nil
///
/// VideoConfigurationView(
///     frameRate: $frameRate,
///     codec: $codec,
///     quality: $quality,
///     interpolationEnabled: $interpolationEnabled,
///     interpolationFactor: $interpolationFactor,
///     interpolationMethod: $interpolationMethod,
///     superResolutionEnabled: $superResolutionEnabled,
///     superResolutionFactor: $superResolutionFactor,
///     superResolutionMethod: $superResolutionMethod
/// )
/// ```
public struct VideoConfigurationView: View {
    @Binding var frameRate: Int
    @Binding var codec: VideoCodec
    @Binding var quality: VideoQuality
    @Binding var interpolationEnabled: Bool
    @Binding var interpolationFactor: Int
    @Binding var interpolationMethod: InterpolationMethod?
    @Binding var interpolationPassMode: InterpolationPassMode
    @Binding var superResolutionEnabled: Bool
    @Binding var superResolutionFactor: Int
    @Binding var superResolutionMethod: SuperResolutionMethod?

    /// Optional frame dimensions for computing available scale factors.
    /// When nil, shows all common options.
    var frameDimensions: CGSize?

    /// Model download state.
    @State private var modelStatus: SuperResolutionModelStatus = .notApplicable
    @State private var isDownloading: Bool = false
    @State private var downloadError: String?

    /// Common frame rate options.
    /// Note: Draw Things currently generates video at 16 FPS (model limitation).
    private let frameRateOptions = [12, 15, 16, 24, 30, 60]

    /// Interpolation factor options.
    private let interpolationFactors = [2, 3, 4]

    /// Target frame rate presets for interpolation.
    /// Based on source 16fps from Draw Things video generation.
    ///
    /// Duration behavior:
    /// - Presets marked "same duration" use factor = fps/16, maintaining original timing
    /// - Presets marked with duration change will alter playback speed
    ///
    /// For example, 81 frames at 16 fps = 5.06 seconds:
    /// - At 24 fps with 2x interpolation (161 frames): 161/24 = 6.7 sec (33% slower)
    /// - At 32 fps with 2x interpolation (161 frames): 161/32 = 5.0 sec (same duration)
    private struct TargetFrameRate: Identifiable, Hashable {
        let fps: Int
        let label: String
        let factor: Int

        var id: Int { fps }

        static let presets: [TargetFrameRate] = [
            // Standard frame rates (will change duration)
            TargetFrameRate(fps: 24, label: "24 fps - Cinematic", factor: 2),
            TargetFrameRate(fps: 30, label: "30 fps - Broadcast", factor: 2),
            // Duration-preserving frame rates
            TargetFrameRate(fps: 32, label: "32 fps - Smooth (same duration)", factor: 2),
            TargetFrameRate(fps: 48, label: "48 fps - High Frame Rate (same duration)", factor: 3),
            TargetFrameRate(fps: 64, label: "64 fps - Ultra Smooth (same duration)", factor: 4),
        ]
    }

    /// Whether VTFrameProcessor is available on this system.
    private var isVTFrameProcessorAvailable: Bool {
        FrameInterpolator.isVTFrameProcessorAvailable
    }

    /// Whether VT super resolution is available on this system.
    private var isVTSuperResolutionAvailable: Bool {
        SuperResolutionScaler.isVTSuperResolutionAvailable
    }

    /// VT Super Resolution only supports 4x scaling.
    /// 2x and 3x will use Core Image Lanczos fallback.
    private let vtSupportedScaleFactors: Set<Int> = [4]

    /// Available super resolution factors based on frame dimensions.
    private var availableSuperResolutionFactors: [Int] {
        guard let dims = frameDimensions else {
            // No dimensions known, show common options
            return [2, 3, 4]
        }

        let width = Int(dims.width)
        let height = Int(dims.height)

        // VT Super Resolution has max input of 1920x1080 for video
        let maxVTWidth = 1920
        let maxVTHeight = 1080

        var factors: [Int] = []

        for factor in [2, 3, 4] {
            // Core Image Lanczos can handle any size, but let's be reasonable
            // Limit to outputs under 8K (7680x4320)
            let outputWidth = width * factor
            let outputHeight = height * factor
            if outputWidth <= 7680 && outputHeight <= 4320 {
                // For VT-supported factors (4x), also check input dimension limits
                if vtSupportedScaleFactors.contains(factor) && isVTSuperResolutionAvailable {
                    // VT requires input <= 1920x1080 for video
                    if width > maxVTWidth || height > maxVTHeight {
                        // VT won't work, but Lanczos will - still allow it
                        factors.append(factor)
                    } else {
                        factors.append(factor)
                    }
                } else {
                    factors.append(factor)
                }
            }
        }

        // Always allow at least 2x via Core Image fallback
        if factors.isEmpty {
            factors = [2]
        }

        return factors
    }

    /// Returns true if the given scale factor will use ML super resolution.
    /// VT Super Resolution only supports 4x; 2x and 3x use Lanczos.
    private func willUseMLSuperResolution(for factor: Int) -> Bool {
        guard isVTSuperResolutionAvailable else { return false }
        guard vtSupportedScaleFactors.contains(factor) else { return false }

        // Check if user explicitly selected Lanczos
        if superResolutionMethod == .coreImageLanczos { return false }

        // Check dimension limits for VT (1920x1080 for video)
        if let dims = frameDimensions {
            if Int(dims.width) > 1920 || Int(dims.height) > 1080 {
                return false
            }
        }

        return true
    }

    public init(
        frameRate: Binding<Int>,
        codec: Binding<VideoCodec>,
        quality: Binding<VideoQuality>,
        interpolationEnabled: Binding<Bool>,
        interpolationFactor: Binding<Int>,
        interpolationMethod: Binding<InterpolationMethod?>,
        interpolationPassMode: Binding<InterpolationPassMode>,
        superResolutionEnabled: Binding<Bool>,
        superResolutionFactor: Binding<Int>,
        superResolutionMethod: Binding<SuperResolutionMethod?>,
        frameDimensions: CGSize? = nil
    ) {
        self._frameRate = frameRate
        self._codec = codec
        self._quality = quality
        self._interpolationEnabled = interpolationEnabled
        self._interpolationFactor = interpolationFactor
        self._interpolationMethod = interpolationMethod
        self._interpolationPassMode = interpolationPassMode
        self._superResolutionEnabled = superResolutionEnabled
        self._superResolutionFactor = superResolutionFactor
        self._superResolutionMethod = superResolutionMethod
        self.frameDimensions = frameDimensions
    }

    public var body: some View {
        Section("Video Output") {
            // Codec
            Picker("Codec", selection: $codec) {
                ForEach(VideoCodec.allCases, id: \.self) { codec in
                    Text(codec.displayName).tag(codec)
                }
            }

            // Quality
            Picker("Quality", selection: $quality) {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }

            // Frame Rate - hidden for now as Draw Things outputs at fixed 16 FPS
            // Uncomment when variable frame rate support is added to Draw Things
            // Picker("Frame Rate", selection: $frameRate) {
            //     ForEach(frameRateOptions, id: \.self) { rate in
            //         Text("\(rate) fps").tag(rate)
            //     }
            // }
        }

        Section("Frame Interpolation") {
            Toggle("Enable Interpolation", isOn: $interpolationEnabled)
                .help("Insert intermediate frames for smoother playback")
                .onChange(of: interpolationEnabled) { _, enabled in
                    if enabled {
                        // Default to 24fps cinematic when enabling
                        if !TargetFrameRate.presets.contains(where: { $0.fps == frameRate }) {
                            frameRate = 24
                        }
                        if let preset = TargetFrameRate.presets.first(where: { $0.fps == frameRate }) {
                            interpolationFactor = preset.factor
                        }
                    }
                }

            if interpolationEnabled {
                Picker("Target Frame Rate", selection: $frameRate) {
                    ForEach(TargetFrameRate.presets) { preset in
                        Text(preset.label).tag(preset.fps)
                    }
                }
                .help("Output video frame rate (source is 16 fps)")
                .onChange(of: frameRate) { _, newFps in
                    // Update interpolation factor based on selected frame rate
                    if let preset = TargetFrameRate.presets.first(where: { $0.fps == newFps }) {
                        interpolationFactor = preset.factor
                    }
                }

                if isVTFrameProcessorAvailable {
                    // User can choose between methods
                    Picker("Method", selection: methodBinding) {
                        Text("Auto (ML-based)").tag(InterpolationMethod?.none)
                        Text("ML Frame Interpolation").tag(InterpolationMethod?.some(.vtFrameProcessor))
                        Text("Cross Dissolve").tag(InterpolationMethod?.some(.coreImageDissolve))
                    }
                    .help("ML-based interpolation provides motion-aware results; Cross Dissolve is faster but lower quality")

                    // Pass mode picker (only relevant for factors > 2)
                    if interpolationFactor > 2 {
                        Picker("Pass Mode", selection: $interpolationPassMode) {
                            ForEach(InterpolationPassMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .help("Multi-pass may reduce artifacts in fast motion scenes but takes longer")
                    }
                } else {
                    // Only Core Image available
                    HStack {
                        Text("Method")
                        Spacer()
                        Text("Cross Dissolve")
                            .foregroundColor(.secondary)
                    }
                    .help("ML-based interpolation requires macOS 15.4 or later")
                }
            }
        }

        Section("Super Resolution") {
            Toggle("Enable Upscaling", isOn: $superResolutionEnabled)
                .help("Upscale video resolution using ML-based super resolution")
                .onChange(of: superResolutionEnabled) { _, enabled in
                    if enabled {
                        // Set to first available factor
                        if !availableSuperResolutionFactors.contains(superResolutionFactor) {
                            superResolutionFactor = availableSuperResolutionFactors.first ?? 2
                        }
                        refreshModelStatus()
                    }
                }

            if superResolutionEnabled {
                Picker("Scale", selection: $superResolutionFactor) {
                    ForEach(availableSuperResolutionFactors, id: \.self) { factor in
                        scaleFactorLabel(factor).tag(factor)
                    }
                }
                .help("Output resolution multiplier")
                .onChange(of: superResolutionFactor) { _, _ in
                    refreshModelStatus()
                }

                if isVTSuperResolutionAvailable {
                    // User can choose between methods
                    // Note: vtLowLatency is omitted as it's designed for real-time use cases
                    // and produces poor results for offline video assembly
                    Picker("Method", selection: superResMethodBinding) {
                        Text("Auto (ML-based)").tag(SuperResolutionMethod?.none)
                        Text("ML Super Resolution").tag(SuperResolutionMethod?.some(.vtSuperResolution))
                        Text("Lanczos Scale").tag(SuperResolutionMethod?.some(.coreImageLanczos))
                    }
                    .help("ML-based upscaling provides better detail; Lanczos is faster but lower quality")
                    .onChange(of: superResolutionMethod) { _, _ in
                        refreshModelStatus()
                    }

                    // Model download status (only for ML Super Resolution)
                    if shouldShowModelStatus {
                        modelStatusView
                    }
                } else {
                    // Only Core Image available
                    HStack {
                        Text("Method")
                        Spacer()
                        Text("Lanczos Scale")
                            .foregroundColor(.secondary)
                    }
                    .help("ML-based super resolution requires macOS 26 or later")
                }
            }
        }
        .onAppear {
            refreshModelStatus()
        }
    }

    /// Creates a label for a scale factor, showing output dimensions and method indicator.
    @ViewBuilder
    private func scaleFactorLabel(_ factor: Int) -> some View {
        let usesML = willUseMLSuperResolution(for: factor)
        let methodIndicator = isVTSuperResolutionAvailable ? (usesML ? " - ML" : " - Lanczos") : ""

        if let dims = frameDimensions {
            let outWidth = Int(dims.width) * factor
            let outHeight = Int(dims.height) * factor
            Text("\(factor)x (\(outWidth)×\(outHeight))\(methodIndicator)")
        } else {
            Text("\(factor)x\(methodIndicator)")
        }
    }

    /// Whether to show model status (only when ML Super Resolution will actually be used).
    private var shouldShowModelStatus: Bool {
        // Only show if ML will actually be used for the current scale factor
        // VT Super Resolution only supports 4x; 2x and 3x always use Lanczos
        guard willUseMLSuperResolution(for: superResolutionFactor) else { return false }

        // Show for Auto (nil) or explicit vtSuperResolution
        // Don't show for coreImageLanczos as it doesn't need model downloads
        return superResolutionMethod == nil || superResolutionMethod == .vtSuperResolution
    }

    /// View showing model download status.
    @ViewBuilder
    private var modelStatusView: some View {
        switch modelStatus {
        case .ready:
            HStack {
                Text("ML Models")
                Spacer()
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .labelStyle(.titleAndIcon)
            }

        case .downloadRequired:
            HStack {
                Text("ML Models")
                Spacer()
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading...")
                        .foregroundColor(.secondary)
                } else {
                    Button("Download") {
                        downloadModels()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let error = downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

        case .downloading(let progress):
            HStack {
                Text("ML Models")
                Spacer()
                ProgressView(value: Double(progress))
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

        case .notApplicable:
            EmptyView()
        }
    }

    /// Refreshes the model status.
    private func refreshModelStatus() {
        modelStatus = SuperResolutionScaler.modelStatus(
            forWidth: 512,
            height: 512,
            scaleFactor: superResolutionFactor
        )
    }

    /// Downloads the ML models.
    private func downloadModels() {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                try await SuperResolutionScaler.downloadModels(
                    forWidth: 512,
                    height: 512,
                    scaleFactor: superResolutionFactor
                )
                await MainActor.run {
                    isDownloading = false
                    refreshModelStatus()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error.localizedDescription
                    refreshModelStatus()
                }
            }
        }
    }

    /// Binding helper for the optional InterpolationMethod picker.
    private var methodBinding: Binding<InterpolationMethod?> {
        Binding(
            get: { interpolationMethod },
            set: { interpolationMethod = $0 }
        )
    }

    /// Binding helper for the optional SuperResolutionMethod picker.
    private var superResMethodBinding: Binding<SuperResolutionMethod?> {
        Binding(
            get: { superResolutionMethod },
            set: { superResolutionMethod = $0 }
        )
    }
}

#Preview {
    Form {
        VideoConfigurationView(
            frameRate: .constant(16),
            codec: .constant(.h264),
            quality: .constant(.high),
            interpolationEnabled: .constant(true),
            interpolationFactor: .constant(4),
            interpolationMethod: .constant(nil),
            interpolationPassMode: .constant(.singlePass),
            superResolutionEnabled: .constant(true),
            superResolutionFactor: .constant(2),
            superResolutionMethod: .constant(nil)
        )
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 500)
}
