import SwiftUI
import SwiftData

/// App-wide: checks who owns the local stats whenever the signed-in account
/// changes, and asks what to do when they belong to a different account (#69).
struct LocalDataOwnershipPrompt: ViewModifier {
    let ownership: LocalDataOwnershipViewModel
    let authService: AuthService
    let modelContext: ModelContext

    private var isShowingChoice: Binding<Bool> {
        Binding(get: { ownership.isShowingChoice }, set: { ownership.isShowingChoice = $0 })
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(get: { ownership.isShowingDeleteConfirmation }, set: { ownership.isShowingDeleteConfirmation = $0 })
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: authService.userId) { _, userId in
                if let userId {
                    ownership.signedIn(userId, modelContext: modelContext)
                } else {
                    ownership.signedOut()
                }
            }
            .alert(LocalDataOwnershipViewModel.choiceTitle, isPresented: isShowingChoice) {
                Button(LocalDataOwnershipViewModel.backUpButton) {
                    ownership.backUpToThisAccount {
                        authService.scheduleBackup(modelContext: modelContext)
                    }
                }
                Button(LocalDataOwnershipViewModel.keepLocalButton) {
                    ownership.keepOnThisDeviceOnly()
                }
                Button(LocalDataOwnershipViewModel.deleteButton, role: .destructive) {
                    ownership.requestDelete()
                }
            } message: {
                Text(LocalDataOwnershipViewModel.choiceMessage)
            }
            .alert(LocalDataOwnershipViewModel.deleteTitle, isPresented: isShowingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    ownership.confirmDelete(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {
                    ownership.cancelDelete()
                }
            } message: {
                Text(LocalDataOwnershipViewModel.deleteMessage)
            }
    }
}
