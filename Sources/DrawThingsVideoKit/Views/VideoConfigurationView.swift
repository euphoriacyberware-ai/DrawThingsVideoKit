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
///
/// VideoConfigurationView(
///     frameRate: $frameRate,
///     codec: $codec,
///     quality: $quality,
///     interpolationEnabled: $interpolationEnabled,
///     interpolationFactor: $interpolationFactor
/// )
/// ```
public struct VideoConfigurationView: View {
    @Binding var frameRate: Int
    @Binding var codec: VideoCodec
    @Binding var quality: VideoQuality
    @Binding var interpolationEnabled: Bool
    @Binding var interpolationFactor: Int

    /// Common frame rate options.
    /// Note: Draw Things currently generates video at 16 FPS (model limitation).
    private let frameRateOptions = [12, 15, 16, 24, 30, 60]

    /// Interpolation factor options.
    private let interpolationFactors = [2, 3, 4]

    public init(
        frameRate: Binding<Int>,
        codec: Binding<VideoCodec>,
        quality: Binding<VideoQuality>,
        interpolationEnabled: Binding<Bool>,
        interpolationFactor: Binding<Int>
    ) {
        self._frameRate = frameRate
        self._codec = codec
        self._quality = quality
        self._interpolationEnabled = interpolationEnabled
        self._interpolationFactor = interpolationFactor
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
                .help("Use VTFrameInterpolation to generate smooth intermediate frames")

            if interpolationEnabled {
                Picker("Multiplier", selection: $interpolationFactor) {
                    ForEach(interpolationFactors, id: \.self) { factor in
                        Text("\(factor)x").tag(factor)
                    }
                }
                .help("Number of frames to generate between each original frame")

                Text("Output will have \(interpolationFactor)x the original frame count")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    Form {
        VideoConfigurationView(
            frameRate: .constant(16),
            codec: .constant(.h264),
            quality: .constant(.high),
            interpolationEnabled: .constant(true),
            interpolationFactor: .constant(2)
        )
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 350)
}
