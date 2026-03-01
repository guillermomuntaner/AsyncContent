import SwiftUI
import Testing
@testable import AsyncContentAsync
@testable import AsyncContentCore
@testable import AsyncContentSwiftUI

private enum InitialError: Error, Equatable, Sendable {
    case failed
}

private enum ReloadError: Error, Equatable, Sendable {
    case failed
}

private enum ActionError: Error, Equatable, Sendable {
    case failed
}

private struct Value: EmptyRepresentable, Equatable, Sendable {
    var items: [Int]

    var isEmpty: Bool {
        items.isEmpty
    }
}

@Test
@MainActor
func effectBindingConsumesOnNilSet() async {
    let store = AsyncContentStore<Value, InitialError, ReloadError, ActionError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.performAction {
        .failure(.failed)
    }

    try? await Task.sleep(for: .milliseconds(30))

    let binding = store.effectBinding()
    #expect(binding.wrappedValue != nil)

    binding.wrappedValue = nil
    #expect(store.nextEffect == nil)
}

@Test
@MainActor
func effectBindingIgnoresNonNilSet() async {
    let store = AsyncContentStore<Value, InitialError, ReloadError, ActionError>(
        resource: .init(phase: .content(.init(items: [1])))
    )
    store.performAction { .failure(.failed) }
    try? await Task.sleep(for: .milliseconds(30))

    let binding = store.effectBinding()
    let before = binding.wrappedValue
    binding.wrappedValue = before

    #expect(store.nextEffect != nil)
}

@Test
@MainActor
func resourceContainerCompilesWithCustomViews() {
    let resource = AsyncContent<Value, InitialError>(phase: .content(.init(items: [])))

    let _: AsyncContentContainer<Value, InitialError, Text> = AsyncContentContainer(
        resource: resource,
        content: { value in Text("items: \(value.items.count)") },
        initialError: { _ in Text("error") },
        empty: { Text("empty") }
    )
}

@Test
@MainActor
func resourceContainerBodyCoversStateBranches() {
    let loading = AsyncContentContainer(
        resource: AsyncContent<Value, InitialError>(phase: .loadingInitial),
        isEmpty: { $0.items.isEmpty },
        content: { _ in Text("c") },
        initialError: { _ in Text("e") },
        empty: { Text("m") }
    )
    _ = loading.body

    let failed = AsyncContentContainer(
        resource: AsyncContent<Value, InitialError>(phase: .failedInitial(.failed)),
        isEmpty: { $0.items.isEmpty },
        content: { _ in Text("c") },
        initialError: { _ in Text("e") },
        empty: { Text("m") }
    )
    _ = failed.body

    let content = AsyncContentContainer(
        resource: AsyncContent<Value, InitialError>(phase: .content(.init(items: [1])), activity: .reloading),
        isEmpty: { $0.items.isEmpty },
        content: { _ in Text("c") },
        initialError: { _ in Text("e") },
        empty: { Text("m") }
    )
    _ = content.body
}

@Test
@MainActor
func resourceContainerCustomInitWithOverlayAndLoadingIsUsable() {
    let container = AsyncContentContainer(
        resource: AsyncContent<Value, InitialError>(phase: .content(.init(items: [1])), activity: .performingAction),
        isEmpty: { $0.items.isEmpty },
        content: { _ in Text("content") },
        loading: { Text("loading") },
        initialError: { _ in Text("error") },
        empty: { Text("empty") },
        overlay: { activity in
            activity == .none ? nil : Text("overlay")
        }
    )

    _ = container.body
}

@Test
@available(iOS 17.0, macOS 14.0, *)
@MainActor
func resourceContainerCompilesWithUnavailableDefaults() {
    let resource = AsyncContent<Value, InitialError>(phase: .failedInitial(.failed))

    let _: AsyncContentContainer<Value, InitialError, Text> = AsyncContentContainer(
        resource: resource,
        isEmpty: { $0.items.isEmpty },
        emptyPresentation: .init(title: "No Items", message: "Nothing here", systemImage: "tray"),
        initialErrorPresentation: { _ in
            .init(title: "Error", message: "Try again", systemImage: "exclamationmark.triangle")
        },
        content: { _ in Text("content") }
    )
}

@Test
@available(iOS 17.0, macOS 14.0, *)
@MainActor
func unavailablePresentationAndObservationStoreAreUsable() async {
    let presentation = UnavailablePresentation(
        title: "No items",
        message: "Try again",
        systemImage: "tray"
    )
    #expect(presentation.title == "No items")

    let base = AsyncContentStore<Value, InitialError, ReloadError, ActionError>(
        resource: .init(phase: .content(.init(items: [1])))
    )
    let observed = ObservableAsyncContentStore(base: base)

    #expect(observed.isCurrentContentEmpty == false)
    #expect(observed.nextEffect == nil)

    observed.load { .success(.init(items: [2])) }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(observed.resource.phase == .content(.init(items: [2])))

    observed.reload { .failure(.failed) }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(observed.nextEffect != nil)
    _ = observed.consumeNextEffect()
    #expect(observed.nextEffect == nil)

    observed.performAction { .success(()) }
    observed.performAction { current in .success(.init(items: current.items + [3])) }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(observed.resource.phase == .content(.init(items: [2, 3])))

    _ = observed.retryInitial()
    _ = observed.retryReload()
    observed.clearEffects()
    observed.cancelReload()
    observed.cancelAction()
    observed.cancelInitialLoad()
    observed.resetToInitial()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(observed.resource.phase == .initial)
}
