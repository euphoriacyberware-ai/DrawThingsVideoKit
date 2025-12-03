//
//  VideoConfigurationView.swift
//  DrawThingsVideoKit
//
//  SwiftUI view for configuring video assembly settings.
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
    private struct TargetFrameRate: Identifiable, Hashable {
        let fps: Int
        let label: String
        let factor: Int

        var id: Int { fps }

        static let presets: [TargetFrameRate] = [
            TargetFrameRate(fps: 24, label: "24 fps - Cinematic", factor: 2),      // 16 * 1.5 ≈ 24
            TargetFrameRate(fps: 25, label: "25 fps - PAL", factor: 2),             // 16 * 1.5625 ≈ 25
            TargetFrameRate(fps: 30, label: "30 fps - NTSC", factor: 2),            // 16 * 1.875 ≈ 30
            TargetFrameRate(fps: 48, label: "48 fps - High Frame Rate", factor: 3), // 16 * 3 = 48
            TargetFrameRate(fps: 60, label: "60 fps - High Motion", factor: 4),     // 16 * 3.75 ≈ 60
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

    /// Available super resolution factors based on frame dimensions and VT limits.
    private var availableSuperResolutionFactors: [Int] {
        guard let dims = frameDimensions else {
            // No dimensions known, show common options
            return [2, 3, 4]
        }

        let width = Int(dims.width)
        let height = Int(dims.height)

        // VT Super Resolution has max input of 1920x1080
        // Filter factors where output would be reasonable and input is within limits
        let maxVTWidth = 1920
        let maxVTHeight = 1080

        var factors: [Int] = []

        for factor in [2, 3, 4] {
            // Check if input dimensions work with VT (if available)
            if isVTSuperResolutionAvailable {
                // VT requires input <= 1920x1080
                if width <= maxVTWidth && height <= maxVTHeight {
                    factors.append(factor)
                }
            } else {
                // Core Image Lanczos can handle any size, but let's be reasonable
                // Limit to outputs under 8K (7680x4320)
                let outputWidth = width * factor
                let outputHeight = height * factor
                if outputWidth <= 7680 && outputHeight <= 4320 {
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

    public init(
        frameRate: Binding<Int>,
        codec: Binding<VideoCodec>,
        quality: Binding<VideoQuality>,
        interpolationEnabled: Binding<Bool>,
        interpolationFactor: Binding<Int>,
        interpolationMethod: Binding<InterpolationMethod?>,
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
                    Picker("Method", selection: superResMethodBinding) {
                        Text("Auto (ML-based)").tag(SuperResolutionMethod?.none)
                        Text("ML Super Resolution").tag(SuperResolutionMethod?.some(.vtSuperResolution))
                        Text("ML Low Latency").tag(SuperResolutionMethod?.some(.vtLowLatency))
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

    /// Creates a label for a scale factor, showing output dimensions if known.
    @ViewBuilder
    private func scaleFactorLabel(_ factor: Int) -> some View {
        if let dims = frameDimensions {
            let outWidth = Int(dims.width) * factor
            let outHeight = Int(dims.height) * factor
            Text("\(factor)x (\(outWidth)×\(outHeight))")
        } else {
            Text("\(factor)x")
        }
    }

    /// Whether to show model status (only for ML Super Resolution method).
    private var shouldShowModelStatus: Bool {
        // Show for Auto (nil) or explicit vtSuperResolution
        // Don't show for vtLowLatency or coreImageLanczos as they don't need model downloads
        superResolutionMethod == nil || superResolutionMethod == .vtSuperResolution
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
            interpolationFactor: .constant(2),
            interpolationMethod: .constant(nil),
            superResolutionEnabled: .constant(true),
            superResolutionFactor: .constant(2),
            superResolutionMethod: .constant(nil)
        )
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 450)
}
