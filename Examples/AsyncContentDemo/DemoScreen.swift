import AsyncContentAsync
import AsyncContentCore
import AsyncContentSwiftUI
import SwiftUI
import Combine

@MainActor
final class DemoViewModel: ObservableObject {
    enum InitialError: Error {
        case network
    }

    enum ReloadError: Error {
        case network
    }

    enum ActionError: Error {
        case failed
    }

    let store = AsyncContentStore<[String], InitialError, ReloadError, ActionError>(
        isEmpty: { $0.isEmpty }
    )
    private var cancellables = Set<AnyCancellable>()

    init() {
        store.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func load() {
        store.load {
            try? await Task.sleep(for: .milliseconds(600))
            return .success(["Ava", "Liam", "Mia"])
        }
    }

    func failLoad() {
        store.load {
            try? await Task.sleep(for: .milliseconds(400))
            return .failure(.network)
        }
    }

    func reload() {
        store.reload {
            try? await Task.sleep(for: .milliseconds(500))
            return .success(["Ava", "Liam", "Mia", "Noah"])
        }
    }

    func failAction() {
        store.performAction {
            try? await Task.sleep(for: .milliseconds(300))
            return .failure(.failed)
        }
    }

    func makeEmpty() {
        store.resetToInitial()
        store.load {
            .success([])
        }
    }
}

struct DemoScreen: View {
    @StateObject private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            AsyncContentContainer(
                resource: viewModel.store.resource,
                isEmpty: { $0.isEmpty },
                content: { users in
                    List(users, id: \.self) { name in
                        Text(name)
                    }
                },
                initialError: { _ in
                    VStack(spacing: 12) {
                        Text("Could not load users")
                        Button("Retry") {
                            _ = viewModel.store.retryInitial()
                        }
                    }
                },
                empty: {
                    Text("No users available")
                }
            )
            .navigationTitle("AsyncContent Demo")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Load") { viewModel.load() }
                    Button("Fail Load") { viewModel.failLoad() }
                    Button("Reload") { viewModel.reload() }
                    Button("Fail Action") { viewModel.failAction() }
                    Button("Empty") { viewModel.makeEmpty() }
                }
            }
            .alert(item: viewModel.store.effectBinding()) { effect in
                if effect.kind == .reloadFailed {
                    return Alert(title: Text("Reload failed"))
                }

                return Alert(title: Text("Action failed"))
            }
            .onAppear {
                viewModel.load()
            }
        }
    }
}

#Preview("Interactive Demo") {
    DemoScreen()
}

#Preview("Loading State") {
    AsyncContentContainer(
        resource: AsyncContent<[String], DemoViewModel.InitialError>(phase: .loadingInitial),
        isEmpty: { $0.isEmpty },
        content: { _ in Text("Loaded") },
        initialError: { _ in Text("Error") },
        empty: { Text("Empty") }
    )
    .padding()
}

#Preview("Loaded State") {
    AsyncContentContainer(
        resource: AsyncContent<[String], DemoViewModel.InitialError>(phase: .content(["Ava", "Liam"])),
        isEmpty: { $0.isEmpty },
        content: { users in
            List(users, id: \.self) { name in
                Text(name)
            }
        },
        initialError: { _ in Text("Error") },
        empty: { Text("Empty") }
    )
}

#Preview("Error State") {
    AsyncContentContainer(
        resource: AsyncContent<[String], DemoViewModel.InitialError>(phase: .failedInitial(.network)),
        isEmpty: { $0.isEmpty },
        content: { _ in Text("Loaded") },
        initialError: { _ in Text("Could not load users") },
        empty: { Text("Empty") }
    )
    .padding()
}
