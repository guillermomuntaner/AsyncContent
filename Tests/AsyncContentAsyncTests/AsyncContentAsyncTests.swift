import Foundation
import Testing
@testable import AsyncContentAsync
@testable import AsyncContentCore

private enum BlockingError: Error, Equatable, Sendable {
    case failed
}

private enum TransientError: Error, Equatable, Sendable {
    case failed
}

private struct Value: EmptyRepresentable, Equatable, Sendable {
    var items: [Int]

    var isEmpty: Bool {
        items.isEmpty
    }
}

private struct NonEmptyAwareValue: Equatable, Sendable {
    var count: Int
}

@Test
@MainActor
func loadSuccessUpdatesState() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()

    store.load {
        try? await Task.sleep(for: .milliseconds(20))
        return .success(.init(items: [1]))
    }

    try? await Task.sleep(for: .milliseconds(60))

    #expect(store.resource.phase == .content(.init(items: [1])))
    #expect(store.resource.activity == .none)
}

@Test
@MainActor
func loadFailureUpdatesInitialError() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()

    store.load {
        .failure(.failed)
    }

    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.resource.phase == .failedInitial(.failed))
}

@Test
@MainActor
func reloadFailureEmitsOneShotEffect() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.reload {
        .failure(.failed)
    }

    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.resource.phase == .content(.init(items: [1])))
    #expect(store.resource.activity == .none)

    switch store.nextEffect {
    case let .some(.reloadFailed(_, error)):
        #expect(error == .failed)
    default:
        #expect(Bool(false), "Expected reload failed effect")
    }

    _ = store.consumeNextEffect()
    #expect(store.nextEffect == nil)
}

@Test
@MainActor
func actionFailureEmitsOneShotEffect() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.performAction {
        .failure(.failed)
    }

    try? await Task.sleep(for: .milliseconds(20))

    switch store.nextEffect {
    case let .some(.actionFailed(_, error)):
        #expect(error == .failed)
    default:
        #expect(Bool(false), "Expected action failed effect")
    }
}

@Test
@MainActor
func secondLoadCancelsFirstByOperationID() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()

    store.load {
        try? await Task.sleep(for: .milliseconds(80))
        return .success(.init(items: [1]))
    }

    store.load {
        try? await Task.sleep(for: .milliseconds(10))
        return .success(.init(items: [2]))
    }

    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.resource.phase == .content(.init(items: [2])))
}

@Test
@MainActor
func supportsConcurrentReloadAndActionChannels() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.reload {
        try? await Task.sleep(for: .milliseconds(30))
        return .success(.init(items: [2]))
    }

    store.performAction {
        try? await Task.sleep(for: .milliseconds(10))
        return .success(())
    }

    #expect(store.resource.activity == .reloadingAndPerformingAction)

    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.resource.activity == .none)
    #expect(store.resource.phase == .content(.init(items: [2])))
}

@Test
@MainActor
func retryInitialReusesLastOperation() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()

    store.load {
        .success(.init(items: [42]))
    }

    try? await Task.sleep(for: .milliseconds(20))

    store.resetToInitial()
    let retried = store.retryInitial()
    #expect(retried)

    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.resource.phase == .content(.init(items: [42])))
}

@Test
@MainActor
func retryInitialWithoutPreviousOperationReturnsFalse() {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()
    #expect(store.retryInitial() == false)
}

@Test
@MainActor
func retryReloadWithoutPreviousOperationReturnsFalse() {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )
    #expect(store.retryReload() == false)
}

@Test
@MainActor
func retryOperationHelpersInvokeProvidedOperation() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.retryInitial(operation: { .success(.init(items: [10])) })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [10])))

    store.retryReload(operation: { .success(.init(items: [11])) })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [11])))
}

@Test
@MainActor
func loadAndReloadThrowingOverloadsMapErrors() async {
    enum TestThrown: Error { case boom }

    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.load(
        operation: { throw TestThrown.boom },
        mapError: { _ in .failed }
    )
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .failedInitial(.failed))

    store.load { .success(.init(items: [1])) }
    try? await Task.sleep(for: .milliseconds(20))

    store.reload(
        operation: { throw TestThrown.boom },
        mapError: { _ in .failed }
    )
    try? await Task.sleep(for: .milliseconds(20))

    if case let .reloadFailed(_, error)? = store.nextEffect {
        #expect(error == .failed)
    } else {
        #expect(Bool(false))
    }
}

@Test
@MainActor
func performActionThrowingOverloadAndValueActionPaths() async {
    enum TestThrown: Error { case boom }
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.performAction(
        operation: { throw TestThrown.boom },
        mapError: { _ in .failed }
    )
    try? await Task.sleep(for: .milliseconds(20))
    if case let .actionFailed(_, error)? = store.nextEffect {
        #expect(error == .failed)
    } else {
        #expect(Bool(false))
    }
    _ = store.consumeNextEffect()

    store.performAction { current in
        .success(.init(items: current.items + [2]))
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [1, 2])))

    store.performAction { (_: Value) in
        .failure(.failed)
    }
    try? await Task.sleep(for: .milliseconds(20))
    if case let .actionFailed(_, error)? = store.nextEffect {
        #expect(error == .failed)
    } else {
        #expect(Bool(false))
    }
}

@Test
@MainActor
func callbackBridgeOverloadsWork() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.load(from: { callback in
        callback(.success(.init(items: [4])))
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [4])))

    store.reload(from: { callback in
        callback(.failure(.failed))
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.nextEffect != nil)
    _ = store.consumeNextEffect()

    store.performAction(from: { callback in
        callback(.failure(.failed))
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.nextEffect != nil)
}

@Test
@MainActor
func cancelMethodsClearInFlightState() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.load {
        try? await Task.sleep(for: .seconds(1))
        return .success(.init(items: [1]))
    }
    #expect(store.resource.phase == .loadingInitial)
    store.cancelInitialLoad()
    #expect(store.resource.phase == .initial)

    store.load { .success(.init(items: [1])) }
    try? await Task.sleep(for: .milliseconds(20))
    store.reload {
        try? await Task.sleep(for: .seconds(1))
        return .success(.init(items: [2]))
    }
    store.performAction {
        try? await Task.sleep(for: .seconds(1))
        return .success(())
    }
    #expect(store.resource.activity == .reloadingAndPerformingAction)
    store.cancelReload()
    #expect(store.resource.activity == .performingAction)
    store.cancelAction()
    #expect(store.resource.activity == .none)
}

@Test
@MainActor
func resetClearsEffects() async {
    let store = AsyncContentStore<Value, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(items: [1])))
    )
    store.performAction { .failure(.failed) }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.nextEffect != nil)

    store.resetToInitial()
    #expect(store.resource.phase == .initial)
    #expect(store.nextEffect == nil)
}

@Test
@MainActor
func defaultIsEmptyClosureReturnsFalseForNonEmptyAwareValue() {
    let store = AsyncContentStore<NonEmptyAwareValue, BlockingError, TransientError>(
        resource: .init(phase: .content(.init(count: 0)))
    )

    #expect(store.isCurrentContentEmpty == false)
}

@Test
@MainActor
func consumeNextEffectReturnsNilWhenQueueEmpty() {
    let store = AsyncContentStore<Value, BlockingError, TransientError>()
    #expect(store.consumeNextEffect() == nil)
}

@Test
@MainActor
func neverTransientErrorFlowHasNoEffectsWhenSuccessful() async {
    let store = AsyncContentStore<Value, BlockingError, Never>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.reload { .success(.init(items: [2])) }
    store.performAction { .success(()) }
    try? await Task.sleep(for: .milliseconds(40))

    #expect(store.nextEffect == nil)
    #expect(store.resource.phase == .content(.init(items: [2])))
}

@Test
@MainActor
func neverTransientConvenienceOverloadsWork() async {
    let store = AsyncContentStore<Value, BlockingError, Never>(
        resource: .init(phase: .content(.init(items: [1])))
    )

    store.reload {
        .init(items: [2])
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [2])))

    store.performAction {
        try? await Task.sleep(for: .milliseconds(5))
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.activity == .none)

    store.performAction { value in
        .init(items: value.items + [3])
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [2, 3])))

    store.reload(from: { callback in
        callback(.init(items: [4]))
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [4])))

    store.performAction(from: { callback in
        callback()
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.activity == .none)

    store.performAction(from: { value, callback in
        callback(.init(items: value.items + [5]))
    })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.resource.phase == .content(.init(items: [4, 5])))
    #expect(store.nextEffect == nil)
}
