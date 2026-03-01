# AsyncContent

SwiftUI-first loading lifecycle primitives with three layers:
- `AsyncContentCore`: model + transitions + composition.
- `AsyncContentAsync`: async/await store, cancellation, retries, callback bridges.
- `AsyncContentSwiftUI`: rendering container and SwiftUI integration helpers.

## Install (SPM)

```swift
.package(url: "https://github.com/your-org/AsyncContent.git", from: "0.1.0")
```

Products:
- `AsyncContentCore`
- `AsyncContentAsync`
- `AsyncContentSwiftUI`

## Quickstart (Out of the Box)

```swift
import AsyncContentAsync
import AsyncContentSwiftUI

@MainActor
final class UsersVM: ObservableObject {
    enum InitialError: Error { case network }
    enum ReloadError: Error { case network }
    enum ActionError: Error { case failed }

    @Published private(set) var store = AsyncContentStore<[String], InitialError, ReloadError, ActionError>(
        isEmpty: { $0.isEmpty }
    )

    func load() {
        store.load {
            .success(["Ana", "Kai"])
        }
    }
}
```

```swift
struct UsersView: View {
    @StateObject private var vm = UsersVM()

    var body: some View {
        AsyncContentContainer(
            resource: vm.store.resource,
            isEmpty: { $0.isEmpty },
            content: { users in
                List(users, id: \.self) { Text($0) }
            },
            initialError: { _ in
                VStack {
                    Text("Could not load users")
                    Button("Retry") { _ = vm.store.retryInitial() }
                }
            },
            empty: {
                Text("No users yet")
            }
        )
        .onAppear { vm.load() }
        .alert(item: vm.store.effectBinding()) { effect in
            switch effect {
            case .reloadFailed:
                return Alert(title: Text("Reload failed"))
            case .actionFailed:
                return Alert(title: Text("Action failed"))
            }
        }
    }
}
```

## Defaults and Overrides

- Default loading UI: `ProgressView`.
- iOS 17+ / macOS 14+ convenience: `ContentUnavailableView` via `UnavailablePresentation`.
- iOS 16 fallback: provide custom `initialError` and `empty` views.

### iOS 17+ convenience API

```swift
@available(iOS 17, *)
let view = AsyncContentContainer(
    resource: store.resource,
    isEmpty: { $0.isEmpty },
    emptyPresentation: .init(
        title: "No items",
        message: "Try changing filters",
        systemImage: "tray"
    ),
    initialErrorPresentation: { _ in
        .init(title: "Something went wrong", message: "Try again", systemImage: "wifi.exclamationmark")
    },
    content: { items in
        List(items, id: \.self) { Text($0) }
    }
)
```

## API Layers

### 1) Low level (`AsyncContentCore`)

Use `AsyncContent` and transitions directly:
- `startInitialLoad`
- `finishInitialSuccess`
- `finishInitialFailure`
- `startReload`
- `finishReloadSuccess`
- `finishReloadFailure`
- `startAction`
- `finishActionSuccess`
- `finishActionFailure`
- `resetToInitial`
- `mapValue`
- `mapInitialError`

### 2) High level (`AsyncContentAsync`)

Use the store helpers:
- `load`
- `reload`
- `performAction`
- `retryInitial`
- `retryReload`
- `cancelInitialLoad`
- `cancelReload`
- `cancelAction`

Single-flight policy per channel:
- one initial task
- one reload task
- one action task

Starting a new task cancels the in-flight task in the same channel.

### 3) SwiftUI (`AsyncContentSwiftUI`)

Use `AsyncContentContainer` and `effectBinding()`.

## Composition

Primary pattern is nested containers. For simple dual-source screens, use `combine2` from `AsyncContentCore`.

## Callback Bridges

All high-level operations expose callback-bridge overloads:
- `load(from:)`
- `reload(from:)`
- `performAction(from:)`

## Testing

The package includes tests for:
- lifecycle state transitions
- one-shot effect emission/consumption
- channel concurrency and cancellation
- composition (`combine2`)
- SwiftUI integration helpers

Run:

```bash
swift test
```

## Demo App

See [`Examples/AsyncContentDemo`](Examples/AsyncContentDemo) for a small sample app source set that demonstrates:
- initial loading and retries
- reload overlays
- action failures as one-shot effects
- default and custom empty/error presentations
