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
///
/// Example usage:
/// ```swift
/// @State private var frameRate: Int = 24
/// @State private var codec: VideoCodec = .h264
/// @State private var quality: VideoQuality = .high
/// @State private var interpolationEnabled: Bool = false
/// @State private var interpolationFactor: Int = 2
/// @State private var interpolationMethod: InterpolationMethod? = nil
///
/// VideoConfigurationView(
///     frameRate: $frameRate,
///     codec: $codec,
///     quality: $quality,
///     interpolationEnabled: $interpolationEnabled,
///     interpolationFactor: $interpolationFactor,
///     interpolationMethod: $interpolationMethod
/// )
/// ```
public struct VideoConfigurationView: View {
    @Binding var frameRate: Int
    @Binding var codec: VideoCodec
    @Binding var quality: VideoQuality
    @Binding var interpolationEnabled: Bool
    @Binding var interpolationFactor: Int
    @Binding var interpolationMethod: InterpolationMethod?

    /// Common frame rate options.
    /// Note: Draw Things currently generates video at 16 FPS (model limitation).
    private let frameRateOptions = [12, 15, 16, 24, 30, 60]

    /// Interpolation factor options.
    private let interpolationFactors = [2, 3, 4]

    /// Whether VTFrameProcessor is available on this system.
    private var isVTFrameProcessorAvailable: Bool {
        FrameInterpolator.isVTFrameProcessorAvailable
    }

    public init(
        frameRate: Binding<Int>,
        codec: Binding<VideoCodec>,
        quality: Binding<VideoQuality>,
        interpolationEnabled: Binding<Bool>,
        interpolationFactor: Binding<Int>,
        interpolationMethod: Binding<InterpolationMethod?>
    ) {
        self._frameRate = frameRate
        self._codec = codec
        self._quality = quality
        self._interpolationEnabled = interpolationEnabled
        self._interpolationFactor = interpolationFactor
        self._interpolationMethod = interpolationMethod
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
            Toggle("Enable Interpolation (2x)", isOn: $interpolationEnabled)
                .help("Insert intermediate frames for smoother playback")
                .onChange(of: interpolationEnabled) { _, enabled in
                    if enabled {
                        interpolationFactor = 2
                    }
                }

            if interpolationEnabled {
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

            // Multiplier picker - hidden for now, defaults to 2x
            // Uncomment to allow user selection of interpolation factor
            // if interpolationEnabled {
            //     Picker("Multiplier", selection: $interpolationFactor) {
            //         ForEach(interpolationFactors, id: \.self) { factor in
            //             Text("\(factor)x").tag(factor)
            //         }
            //     }
            //     .help("Number of frames to generate between each original frame")
            // }
        }
    }

    /// Binding helper for the optional InterpolationMethod picker.
    private var methodBinding: Binding<InterpolationMethod?> {
        Binding(
            get: { interpolationMethod },
            set: { interpolationMethod = $0 }
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
            interpolationMethod: .constant(nil)
        )
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 350)
}
