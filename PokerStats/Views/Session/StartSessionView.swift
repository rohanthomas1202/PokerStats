import SwiftUI
import SwiftData

struct StartSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NewSessionViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "suit.club.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.pokerAccent)
                    Text("New Session")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top, 20)

                // Buy-in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Buy-In")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    CurrencyField(title: "Amount", text: $viewModel.buyInText)
                }

                // Stakes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stakes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CommonStakes.allCases) { stakes in
                                Button {
                                    viewModel.selectedStakes = stakes.rawValue
                                } label: {
                                    Text(stakes.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            viewModel.selectedStakes == stakes.rawValue
                                                ? Color.pokerAccent
                                                : Color.pokerCard
                                        )
                                        .foregroundStyle(
                                            viewModel.selectedStakes == stakes.rawValue
                                                ? .white
                                                : .primary
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if viewModel.selectedStakes == "Custom" {
                        TextField("e.g. 5/10", text: $viewModel.customStakes)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Location
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("Casino or home game", text: $viewModel.location)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer(minLength: 40)

                // Start button
                Button {
                    _ = viewModel.createSession(in: modelContext)
                } label: {
                    Text("Start Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isValid ? Color.pokerAccent : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!viewModel.isValid)
            }
            .padding()
        }
        .navigationTitle("Session")
        .onAppear {
            viewModel.loadDefaults(from: modelContext)
        }
    }
}
