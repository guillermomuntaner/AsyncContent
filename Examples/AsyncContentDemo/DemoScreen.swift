import AsyncContentAsync
import AsyncContentCore
import AsyncContentSwiftUI
import SwiftUI
import Combine

enum DemoUIError: Error, Equatable, Sendable {
    case loadFailed
    case transientFailed
}

typealias DemoContentStore<Value: Sendable> = AsyncContentStore<Value, DemoUIError, DemoUIError>

struct DemoAsyncContentContainer<Value, Content: View>: View {
    let resource: AsyncContent<Value, DemoUIError>
    let isEmpty: (Value) -> Bool
    let content: (Value) -> Content
    var retry: (() -> Void)?

    var body: some View {
        AsyncContentContainer(
            resource: resource,
            isEmpty: isEmpty,
            content: content,
            loading: {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            },
            initialError: { _ in
                VStack(spacing: 12) {
                    Text("Could not load users")
                    Button("Retry") {
                        retry?()
                    }
                }
            },
            empty: {
                if #available(iOS 17.0, macOS 14.0, *) {
                    ContentUnavailableView("No users available", systemImage: "person.2.slash")
                } else {
                    Text("No users available")
                }
            },
            overlay: { activity in
                if activity != .none {
                    ProgressView(activity == .reloading ? "Refreshing..." : "Updating...")
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        )
    }
}

@MainActor
final class DemoViewModel: ObservableObject {
    let store = DemoContentStore<[String]>(
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
            return .failure(.loadFailed)
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
            return .failure(.transientFailed)
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
            DemoAsyncContentContainer(
                resource: viewModel.store.resource,
                isEmpty: { $0.isEmpty },
                content: { users in
                    List(users, id: \.self) { name in
                        Text(name)
                    }
                },
                retry: {
                    _ = viewModel.store.retryInitial()
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
    DemoAsyncContentContainer(
        resource: AsyncContent<[String], DemoUIError>(phase: .loadingInitial),
        isEmpty: { $0.isEmpty },
        content: { _ in Text("Loaded") },
        retry: nil
    )
    .padding()
}

#Preview("Loaded State") {
    DemoAsyncContentContainer(
        resource: AsyncContent<[String], DemoUIError>(phase: .content(["Ava", "Liam"])),
        isEmpty: { $0.isEmpty },
        content: { users in
            List(users, id: \.self) { name in
                Text(name)
            }
        },
        retry: nil
    )
}

#Preview("Error State") {
    DemoAsyncContentContainer(
        resource: AsyncContent<[String], DemoUIError>(phase: .failedInitial(.loadFailed)),
        isEmpty: { $0.isEmpty },
        content: { _ in Text("Loaded") },
        retry: nil
    )
    .padding()
}
