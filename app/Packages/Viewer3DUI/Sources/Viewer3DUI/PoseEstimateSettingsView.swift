import SwiftUI

/// Settings popover for the 2D Pose Estimate tool.
/// Allows configuring topic, reference frame, and covariance values.
struct PoseEstimateSettingsView: View {
    @Binding var topic: String
    @Binding var frame: String
    @Binding var covXY: Double
    @Binding var covYaw: Double
    let availableFrames: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pose Estimate Settings")
                .font(.headline)
                .padding(.bottom, 4)

            // Topic
            VStack(alignment: .leading, spacing: 4) {
                Text("Topic").font(.caption).foregroundStyle(.secondary)
                TextField("/initialpose", text: $topic)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            // Frame
            VStack(alignment: .leading, spacing: 4) {
                Text("Reference Frame").font(.caption).foregroundStyle(.secondary)
                if availableFrames.isEmpty {
                    TextField("map", text: $frame)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Frame", selection: $frame) {
                        ForEach(availableFrames, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Divider()

            // Covariance — diagonal only
            Text("Covariance (diagonal)").font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Position XY (m²)").frame(width: 130, alignment: .leading)
                TextField("0.25", value: $covXY, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            HStack {
                Text("Z (m²)").frame(width: 130, alignment: .leading)
                Text("0.001")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
            }

            HStack {
                Text("Rotation (rad²)").frame(width: 130, alignment: .leading)
                TextField("0.0685", value: $covYaw, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Divider()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 260)
        .onAppear {
            // Default frame to "map" if available and not already set
            if frame == "map" && !availableFrames.contains("map") {
                // Keep "map" as default even if not in the live list
            } else if availableFrames.contains("map") && frame.isEmpty {
                frame = "map"
            }
        }
    }
}
