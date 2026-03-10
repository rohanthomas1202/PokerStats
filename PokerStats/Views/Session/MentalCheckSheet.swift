import SwiftUI

struct MentalCheckSheet: View {
    @Binding var tiltLevel: Int
    @Binding var energyLevel: Int
    @Binding var focusLevel: Int
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How are you feeling?")
                    .font(.headline)
                    .padding(.top)

                MentalMetricSlider(metricType: .tilt, value: $tiltLevel)
                MentalMetricSlider(metricType: .energy, value: $energyLevel)
                MentalMetricSlider(metricType: .focus, value: $focusLevel)

                Button {
                    onSave()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pokerAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Mental Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
