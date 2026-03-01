import Foundation
import Testing
@testable import AsyncContentCore

private enum TestInitialError: Error, Equatable, Sendable {
    case failed
}

private enum TestReloadError: Error, Equatable, Sendable {
    case failed
}

private enum TestActionError: Error, Equatable, Sendable {
    case failed
}

private struct TestValue: EmptyRepresentable, Equatable, Sendable {
    var items: [Int]

    var isEmpty: Bool {
        items.isEmpty
    }
}

@Test
func initialLoadTransitions() {
    var resource = AsyncContent<TestValue, TestInitialError>()

    #expect(resource.phase == .initial)
    #expect(resource.activity == .none)

    resource.startInitialLoad()
    #expect(resource.phase == .loadingInitial)

    resource.finishInitialSuccess(.init(items: [1]))
    #expect(resource.phase == .content(.init(items: [1])))
    #expect(resource.activity == .none)
}

@Test
func initialFailureTransitions() {
    var resource = AsyncContent<TestValue, TestInitialError>()

    resource.startInitialLoad()
    resource.finishInitialFailure(.failed)

    #expect(resource.phase == .failedInitial(.failed))
    #expect(resource.value == nil)
    #expect(resource.initialError == .failed)
}

@Test
func reloadFailureEmitsEffectAndKeepsContent() {
    var resource = AsyncContent<TestValue, TestInitialError>(phase: .content(.init(items: [1])))

    let didStartReload = resource.startReload()
    #expect(didStartReload)
    #expect(resource.activity == .reloading)

    let effect = resource.finishReloadFailure(TestReloadError.failed)

    #expect(resource.activity == .none)
    #expect(resource.phase == .content(.init(items: [1])))

    switch effect {
    case let .some(.reloadFailed(_, error)):
        #expect(error == .failed)
    default:
        #expect(Bool(false), "Expected reload failure effect")
    }
}

@Test
func actionFailureEmitsEffectAndClearsActivity() {
    var resource = AsyncContent<TestValue, TestInitialError>(phase: .content(.init(items: [1])))

    let didStartAction = resource.startAction()
    #expect(didStartAction)
    #expect(resource.activity == .performingAction)

    let effect = resource.finishActionFailure(TestActionError.failed)

    #expect(resource.activity == .none)

    switch effect {
    case let .some(.actionFailed(_, error)):
        #expect(error == .failed)
    default:
        #expect(Bool(false), "Expected action failure effect")
    }
}

@Test
func supportsConcurrentChannels() {
    var resource = AsyncContent<TestValue, TestInitialError>(phase: .content(.init(items: [1])))

    let didStartReload = resource.startReload()
    #expect(didStartReload)
    #expect(resource.activity == .reloading)

    let didStartAction = resource.startAction()
    #expect(didStartAction)
    #expect(resource.activity == .reloadingAndPerformingAction)

    resource.finishActionSuccess()
    #expect(resource.activity == .reloading)

    _ = resource.finishReloadSuccess(.init(items: [2]))
    #expect(resource.activity == .none)
    #expect(resource.phase == .content(.init(items: [2])))
}

@Test
func mapUtilitiesKeepActivity() {
    let resource = AsyncContent<Int, TestInitialError>(phase: .failedInitial(.failed), activity: .performingAction)

    let mappedValue = resource.mapValue { "\($0)" }
    #expect(mappedValue.activity == .performingAction)

    let mappedError = resource.mapInitialError { _ in "boom" }
    #expect(mappedError.phase == .failedInitial("boom"))
}

@Test
func emptyDetectionWorks() {
    let resource = AsyncContent<TestValue, TestInitialError>(phase: .content(.init(items: [])))

    #expect(resource.isContentEmpty)
    #expect(resource.isContentEmpty(using: { $0.items.isEmpty }))
}

@Test
func combine2BuildsCombinedContent() {
    let left = AsyncContent<Int, TestInitialError>(phase: .content(1), activity: .reloading)
    let right = AsyncContent<String, TestInitialError>(phase: .content("A"), activity: .performingAction)

    let combined = combine2(left, right)

    switch combined.phase {
    case let .content(value):
        #expect(value.0 == 1)
        #expect(value.1 == "A")
    default:
        #expect(Bool(false), "Expected combined content")
    }
    #expect(combined.activity == .reloadingAndPerformingAction)
}

@Test
func combine2BuildsCombinedInitialError() {
    let left = AsyncContent<Int, TestInitialError>(phase: .failedInitial(.failed))
    let right = AsyncContent<String, TestInitialError>(phase: .failedInitial(.failed))

    let combined = combine2(left, right)

    switch combined.phase {
    case let .failedInitial(error):
        #expect(error == .both(.failed, .failed))
    default:
        #expect(Bool(false), "Expected combined initial failure")
    }
}

@Test
func guardPathsWithoutContentReturnFalseOrNil() {
    var resource = AsyncContent<TestValue, TestInitialError>()

    #expect(resource.startReload() == false)
    #expect(resource.finishReloadSuccess(.init(items: [1])) == false)
    #expect(resource.finishReloadFailure(TestReloadError.failed) == nil)

    #expect(resource.startAction() == false)
    #expect(resource.finishActionFailure(TestActionError.failed) == nil)
}

@Test
func setContentAndResetRoundTrip() {
    var resource = AsyncContent<TestValue, TestInitialError>()
    resource.setContent(.init(items: [1, 2]))

    #expect(resource.phase == .content(.init(items: [1, 2])))
    #expect(resource.activity == .none)

    resource.resetToInitial()
    #expect(resource.phase == .initial)
    #expect(resource.activity == .none)
}

@Test
func mapValueCoversAllPhaseBranches() {
    let initial = AsyncContent<Int, TestInitialError>(phase: .initial)
    let loading = AsyncContent<Int, TestInitialError>(phase: .loadingInitial)
    let content = AsyncContent<Int, TestInitialError>(phase: .content(3))

    #expect(initial.mapValue { "\($0)" }.phase == .initial)
    #expect(loading.mapValue { "\($0)" }.phase == .loadingInitial)
    #expect(content.mapValue { "\($0)" }.phase == .content("3"))
}

@Test
func mapInitialErrorCoversAllPhaseBranches() {
    let initial = AsyncContent<Int, TestInitialError>(phase: .initial)
    let loading = AsyncContent<Int, TestInitialError>(phase: .loadingInitial)
    let content = AsyncContent<Int, TestInitialError>(phase: .content(3))

    #expect(initial.mapInitialError { _ in "x" }.phase == .initial)
    #expect(loading.mapInitialError { _ in "x" }.phase == .loadingInitial)
    #expect(content.mapInitialError { _ in "x" }.phase == .content(3))
}

@Test
func effectHelpersAndKindWork() {
    let id1 = UUID()
    let id2 = UUID()

    let reload = AsyncContentEffect<TestReloadError, TestActionError>.makeReloadFailed(error: .failed, id: id1)
    let action = AsyncContentEffect<TestReloadError, TestActionError>.makeActionFailed(error: .failed, id: id2)

    #expect(reload.id == id1)
    #expect(action.id == id2)
    #expect(reload.kind == .reloadFailed)
    #expect(action.kind == .actionFailed)
}

@Test
func combine2CoversLeftRightFailureLoadingAndInitial() {
    let leftFailure = AsyncContent<Int, TestInitialError>(phase: .failedInitial(.failed))
    let rightFailure = AsyncContent<String, TestInitialError>(phase: .failedInitial(.failed))
    let loading = AsyncContent<String, TestInitialError>(phase: .loadingInitial)
    let initial = AsyncContent<String, TestInitialError>(phase: .initial)

    let leftOnly = combine2(leftFailure, initial)
    let rightOnly = combine2(initial.mapValue { _ in 1 }, rightFailure)
    let loadingCombined = combine2(initial.mapValue { _ in 1 }, loading)
    let initialCombined = combine2(initial.mapValue { _ in 1 }, initial)

    switch leftOnly.phase {
    case let .failedInitial(error):
        #expect(error == .left(.failed))
    default:
        #expect(Bool(false))
    }
    switch rightOnly.phase {
    case let .failedInitial(error):
        #expect(error == .right(.failed))
    default:
        #expect(Bool(false))
    }
    switch loadingCombined.phase {
    case .loadingInitial:
        #expect(Bool(true))
    default:
        #expect(Bool(false))
    }
    switch initialCombined.phase {
    case .initial:
        #expect(Bool(true))
    default:
        #expect(Bool(false))
    }
}

@Test
func mergeEffectsAndTaggedIdWork() {
    let leftID = UUID()
    let rightID = UUID()
    let left: [AsyncContentEffect<TestReloadError, TestActionError>] = [
        .reloadFailed(id: leftID, error: .failed)
    ]
    let right: [AsyncContentEffect<String, String>] = [
        .actionFailed(id: rightID, error: "boom")
    ]

    let merged = mergeEffects(left: left, right: right)
    #expect(merged.count == 2)

    #expect(merged[0].source == .left)
    #expect(merged[1].source == .right)
    #expect(merged[0].id.contains(leftID.uuidString))
    #expect(merged[1].id.contains(rightID.uuidString))
}

@Test
func mapErrorsCoversBothCases() {
    let reload = AsyncContentEffect<TestReloadError, TestActionError>.reloadFailed(id: UUID(), error: .failed)
    let action = AsyncContentEffect<TestReloadError, TestActionError>.actionFailed(id: UUID(), error: .failed)

    let mappedReload = reload.mapErrors(reload: { _ in "r" }, action: { _ in "a" })
    let mappedAction = action.mapErrors(reload: { _ in "r" }, action: { _ in "a" })

    switch mappedReload {
    case let .reloadFailed(_, error):
        #expect(error == "r")
    default:
        #expect(Bool(false))
    }

    switch mappedAction {
    case let .actionFailed(_, error):
        #expect(error == "a")
    default:
        #expect(Bool(false))
    }
}

@Test
func unionActivityThroughCombineCoversSingleFlags() {
    let baseLeft = AsyncContent<Int, TestInitialError>(phase: .content(1), activity: .reloading)
    let baseRight = AsyncContent<String, TestInitialError>(phase: .content("a"), activity: .none)
    #expect(combine2(baseLeft, baseRight).activity == .reloading)

    let actionLeft = AsyncContent<Int, TestInitialError>(phase: .content(1), activity: .performingAction)
    #expect(combine2(actionLeft, baseRight).activity == .performingAction)
}
