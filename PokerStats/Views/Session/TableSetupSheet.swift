import SwiftUI

struct TableSetupSheet: View {
    @Bindable var viewModel: ActiveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingSeatIndex: Int? = nil
    @State private var editingName: String = ""
    @State private var selectedSeatIndex: Int? = nil
    @State private var config: TableConfig

    init(viewModel: ActiveSessionViewModel) {
        self.viewModel = viewModel
        self._config = State(initialValue: viewModel.session.tableConfig ?? PositionTracker.createConfig(totalSeats: 6))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Table info
                HStack {
                    Text("\(config.activePlayerCount) Players")
                        .font(.headline)
                    Spacer()
                    if config.isCalibrated {
                        let pos = PositionTracker.heroPosition(config: config)
                        if pos != .unknown {
                            Text("You: \(pos.longName)")
                                .font(.subheadline)
                                .foregroundStyle(Color.pokerAccent)
                        }
                    }
                }
                .padding(.horizontal)

                // Circular table
                tableVisualization
                    .frame(height: 280)
                    .padding(.horizontal)

                // Quick actions
                quickActions
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Table Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.updateTableConfig(config)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                seatDialogTitle,
                isPresented: .init(
                    get: { selectedSeatIndex != nil },
                    set: { if !$0 { selectedSeatIndex = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let idx = selectedSeatIndex, idx < config.seats.count, config.seats[idx].isOccupied {
                    Button("Set as Dealer") {
                        config.buttonSeatIndex = idx
                        selectedSeatIndex = nil
                    }
                    Button("Rename") {
                        editingName = config.seats[idx].playerName
                        editingSeatIndex = idx
                        selectedSeatIndex = nil
                    }
                    if idx != config.heroSeatIndex {
                        Button("Remove Player", role: .destructive) {
                            config = PositionTracker.removePlayer(at: idx, config: config)
                            selectedSeatIndex = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        selectedSeatIndex = nil
                    }
                }
            }
            .alert("Rename Player", isPresented: .init(
                get: { editingSeatIndex != nil },
                set: { if !$0 { editingSeatIndex = nil } }
            )) {
                TextField("Player name", text: $editingName)
                Button("Save") {
                    if let idx = editingSeatIndex {
                        config.seats[idx].playerName = editingName
                    }
                    editingSeatIndex = nil
                }
                Button("Cancel", role: .cancel) {
                    editingSeatIndex = nil
                }
            } message: {
                Text("Enter a name for this player")
            }
        }
    }

    // MARK: - Circular Table

    private var tableVisualization: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 40

            // Table felt (green oval)
            Ellipse()
                .fill(Color.green.opacity(0.15))
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                .frame(width: radius * 1.4, height: radius * 1.0)
                .position(center)

            // Seats
            ForEach(config.seats) { seat in
                let angle = seatAngle(index: seat.index, total: config.seats.count)
                let seatCenter = CGPoint(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )

                seatView(seat: seat)
                    .position(seatCenter)
            }
        }
    }

    private func seatAngle(index: Int, total: Int) -> CGFloat {
        let startAngle = -CGFloat.pi / 2
        return startAngle + (2 * CGFloat.pi * CGFloat(index) / CGFloat(total))
    }

    private func seatView(seat: TableSeat) -> some View {
        let isHero = seat.index == config.heroSeatIndex
        let isButton = seat.index == config.buttonSeatIndex

        return Button {
            handleSeatTap(seat)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(seatColor(seat: seat, isHero: isHero))
                        .frame(width: 44, height: 44)

                    if seat.isOccupied {
                        Text(seatInitial(seat: seat, isHero: isHero))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Button marker
                    if isButton && config.buttonSeatIndex >= 0 {
                        Text("D")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(Color.yellow, in: Circle())
                            .offset(x: 16, y: -16)
                    }
                }

                Text(seat.displayName)
                    .font(.caption2)
                    .foregroundStyle(isHero ? Color.pokerAccent : .secondary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
    }

    private func seatColor(seat: TableSeat, isHero: Bool) -> Color {
        if !seat.isOccupied {
            return Color.gray.opacity(0.3)
        }
        if isHero {
            return Color.pokerAccent
        }
        return Color.pokerCard.opacity(0.8)
    }

    private func seatInitial(seat: TableSeat, isHero: Bool) -> String {
        if isHero { return "H" }
        if seat.playerName.isEmpty { return "\(seat.index + 1)" }
        return String(seat.playerName.prefix(1)).uppercased()
    }

    private func handleSeatTap(_ seat: TableSeat) {
        if seat.isOccupied {
            selectedSeatIndex = seat.index
        } else {
            // Empty seat — add player back
            config = PositionTracker.addPlayer(at: seat.index, config: config)
        }
    }

    private var seatDialogTitle: String {
        guard let idx = selectedSeatIndex, idx < config.seats.count else { return "" }
        let seat = config.seats[idx]
        let name = seat.displayName
        let isHero = idx == config.heroSeatIndex
        return isHero ? "\(name) (You)" : name
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    if let seat = config.seats.last(where: { $0.isOccupied && $0.index != config.heroSeatIndex }) {
                        config = PositionTracker.removePlayer(at: seat.index, config: config)
                    }
                } label: {
                    Label("Remove Player", systemImage: "person.badge.minus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(config.activePlayerCount <= 2)

                Button {
                    if let emptySeat = config.seats.first(where: { !$0.isOccupied }) {
                        config = PositionTracker.addPlayer(at: emptySeat.index, config: config)
                    } else if config.seats.count < 9 {
                        config = PositionTracker.addSeat(config: config)
                    }
                } label: {
                    Label("Add Player", systemImage: "person.badge.plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Color.pokerAccent)
                .disabled(config.activePlayerCount >= 9)
            }

            Text("Tap a player to set dealer, rename, or remove")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
