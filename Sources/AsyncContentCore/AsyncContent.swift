import Foundation

public protocol EmptyRepresentable {
    var isEmpty: Bool { get }
}

public enum AsyncContentPhase<Value, InitialError> {
    case initial
    case loadingInitial
    case content(Value)
    case failedInitial(InitialError)
}

public enum AsyncContentActivity: Sendable {
    case none
    case reloading
    case performingAction
    case reloadingAndPerformingAction

    public var isReloading: Bool {
        switch self {
        case .reloading, .reloadingAndPerformingAction:
            return true
        case .none, .performingAction:
            return false
        }
    }

    public var isPerformingAction: Bool {
        switch self {
        case .performingAction, .reloadingAndPerformingAction:
            return true
        case .none, .reloading:
            return false
        }
    }

    public func settingReloading(_ enabled: Bool) -> Self {
        Self.make(reloading: enabled, action: isPerformingAction)
    }

    public func settingPerformingAction(_ enabled: Bool) -> Self {
        Self.make(reloading: isReloading, action: enabled)
    }

    private static func make(reloading: Bool, action: Bool) -> Self {
        switch (reloading, action) {
        case (false, false):
            return .none
        case (true, false):
            return .reloading
        case (false, true):
            return .performingAction
        case (true, true):
            return .reloadingAndPerformingAction
        }
    }
}

public struct AsyncContent<Value, InitialError> {
    public var phase: AsyncContentPhase<Value, InitialError>
    public var activity: AsyncContentActivity

    public init(
        phase: AsyncContentPhase<Value, InitialError> = .initial,
        activity: AsyncContentActivity = .none
    ) {
        self.phase = phase
        self.activity = activity
    }

    public var value: Value? {
        guard case let .content(value) = phase else {
            return nil
        }

        return value
    }

    public var initialError: InitialError? {
        guard case let .failedInitial(error) = phase else {
            return nil
        }

        return error
    }

    public var hasContent: Bool {
        value != nil
    }

    public func isContentEmpty(using isEmpty: (Value) -> Bool) -> Bool {
        guard let value else {
            return false
        }

        return isEmpty(value)
    }
}

public extension AsyncContent where Value: EmptyRepresentable {
    var isContentEmpty: Bool {
        value?.isEmpty ?? false
    }
}

public extension AsyncContent {
    mutating func startInitialLoad() {
        phase = .loadingInitial
        activity = .none
    }

    mutating func finishInitialSuccess(_ value: Value) {
        phase = .content(value)
        activity = .none
    }

    mutating func finishInitialFailure(_ error: InitialError) {
        phase = .failedInitial(error)
        activity = .none
    }

    @discardableResult
    mutating func startReload() -> Bool {
        guard hasContent else {
            return false
        }

        activity = activity.settingReloading(true)
        return true
    }

    @discardableResult
    mutating func finishReloadSuccess(_ value: Value) -> Bool {
        guard hasContent else {
            return false
        }

        phase = .content(value)
        activity = activity.settingReloading(false)
        return true
    }

    mutating func finishReloadFailure<ReloadError>(
        _ error: ReloadError,
        id: UUID = UUID()
    ) -> AsyncContentEffect<ReloadError, Never>? {
        guard hasContent else {
            return nil
        }

        activity = activity.settingReloading(false)
        return .reloadFailed(id: id, error: error)
    }

    @discardableResult
    mutating func startAction() -> Bool {
        guard hasContent else {
            return false
        }

        activity = activity.settingPerformingAction(true)
        return true
    }

    mutating func finishActionSuccess() {
        activity = activity.settingPerformingAction(false)
    }

    mutating func finishActionFailure<ActionError>(
        _ error: ActionError,
        id: UUID = UUID()
    ) -> AsyncContentEffect<Never, ActionError>? {
        guard hasContent else {
            return nil
        }

        activity = activity.settingPerformingAction(false)
        return .actionFailed(id: id, error: error)
    }

    mutating func resetToInitial() {
        phase = .initial
        activity = .none
    }

    mutating func setContent(_ value: Value) {
        phase = .content(value)
        activity = .none
    }

    func mapValue<NewValue>(_ transform: (Value) -> NewValue) -> AsyncContent<NewValue, InitialError> {
        let nextPhase: AsyncContentPhase<NewValue, InitialError>
        switch phase {
        case .initial:
            nextPhase = .initial
        case .loadingInitial:
            nextPhase = .loadingInitial
        case let .content(value):
            nextPhase = .content(transform(value))
        case let .failedInitial(error):
            nextPhase = .failedInitial(error)
        }

        return AsyncContent<NewValue, InitialError>(phase: nextPhase, activity: activity)
    }

    func mapInitialError<NewInitialError>(
        _ transform: (InitialError) -> NewInitialError
    ) -> AsyncContent<Value, NewInitialError> {
        let nextPhase: AsyncContentPhase<Value, NewInitialError>
        switch phase {
        case .initial:
            nextPhase = .initial
        case .loadingInitial:
            nextPhase = .loadingInitial
        case let .content(value):
            nextPhase = .content(value)
        case let .failedInitial(error):
            nextPhase = .failedInitial(transform(error))
        }

        return AsyncContent<Value, NewInitialError>(phase: nextPhase, activity: activity)
    }
}

public enum AsyncContentEffect<ReloadError, ActionError>: Identifiable {
    case reloadFailed(id: UUID, error: ReloadError)
    case actionFailed(id: UUID, error: ActionError)

    public var id: UUID {
        switch self {
        case let .reloadFailed(id, _), let .actionFailed(id, _):
            return id
        }
    }

    public static func makeReloadFailed(error: ReloadError, id: UUID = UUID()) -> Self {
        .reloadFailed(id: id, error: error)
    }

    public static func makeActionFailed(error: ActionError, id: UUID = UUID()) -> Self {
        .actionFailed(id: id, error: error)
    }
}

public enum AsyncContentEffectKind: Sendable, Equatable {
    case reloadFailed
    case actionFailed
}

public extension AsyncContentEffect {
    var kind: AsyncContentEffectKind {
        switch self {
        case .reloadFailed:
            return .reloadFailed
        case .actionFailed:
            return .actionFailed
        }
    }
}

extension AsyncContentPhase: Equatable where Value: Equatable, InitialError: Equatable {}
extension AsyncContentPhase: Sendable where Value: Sendable, InitialError: Sendable {}

extension AsyncContent: Equatable where Value: Equatable, InitialError: Equatable {}
extension AsyncContent: Sendable where Value: Sendable, InitialError: Sendable {}

extension AsyncContentEffect: Equatable where ReloadError: Equatable, ActionError: Equatable {}
extension AsyncContentEffect: Sendable where ReloadError: Sendable, ActionError: Sendable {}

public enum CombinedInitialError<LeftError, RightError> {
    case left(LeftError)
    case right(RightError)
    case both(LeftError, RightError)
}

extension CombinedInitialError: Equatable where LeftError: Equatable, RightError: Equatable {}
extension CombinedInitialError: Sendable where LeftError: Sendable, RightError: Sendable {}

public enum CombinedEffectSource: Sendable {
    case left
    case right
}

public struct TaggedEffect<ReloadError, ActionError>: Identifiable {
    public let source: CombinedEffectSource
    public let effect: AsyncContentEffect<ReloadError, ActionError>

    public init(source: CombinedEffectSource, effect: AsyncContentEffect<ReloadError, ActionError>) {
        self.source = source
        self.effect = effect
    }

    public var id: String {
        "\(source)-\(effect.id.uuidString)"
    }
}

extension TaggedEffect: Equatable where ReloadError: Equatable, ActionError: Equatable {}
extension TaggedEffect: Sendable where ReloadError: Sendable, ActionError: Sendable {}

public func combine2<LeftValue, LeftInitialError, RightValue, RightInitialError>(
    _ left: AsyncContent<LeftValue, LeftInitialError>,
    _ right: AsyncContent<RightValue, RightInitialError>
) -> AsyncContent<(LeftValue, RightValue), CombinedInitialError<LeftInitialError, RightInitialError>> {
    let phase: AsyncContentPhase<(LeftValue, RightValue), CombinedInitialError<LeftInitialError, RightInitialError>>

    switch (left.phase, right.phase) {
    case let (.content(leftValue), .content(rightValue)):
        phase = .content((leftValue, rightValue))
    case let (.failedInitial(leftError), .failedInitial(rightError)):
        phase = .failedInitial(.both(leftError, rightError))
    case let (.failedInitial(leftError), _):
        phase = .failedInitial(.left(leftError))
    case let (_, .failedInitial(rightError)):
        phase = .failedInitial(.right(rightError))
    case (.loadingInitial, _), (_, .loadingInitial):
        phase = .loadingInitial
    default:
        phase = .initial
    }

    let activity = unionActivity(left.activity, right.activity)
    return AsyncContent<(LeftValue, RightValue), CombinedInitialError<LeftInitialError, RightInitialError>>(
        phase: phase,
        activity: activity
    )
}

public func mergeEffects<LeftReloadError, LeftActionError, RightReloadError, RightActionError>(
    left: [AsyncContentEffect<LeftReloadError, LeftActionError>],
    right: [AsyncContentEffect<RightReloadError, RightActionError>]
) -> [TaggedEffect<EitherError<LeftReloadError, RightReloadError>, EitherError<LeftActionError, RightActionError>>] {
    let leftEffects: [TaggedEffect<EitherError<LeftReloadError, RightReloadError>, EitherError<LeftActionError, RightActionError>>] = left.map {
        TaggedEffect<EitherError<LeftReloadError, RightReloadError>, EitherError<LeftActionError, RightActionError>>(
            source: .left,
            effect: $0.mapErrors(
                reload: { .left($0) },
                action: { .left($0) }
            )
        )
    }

    let rightEffects: [TaggedEffect<EitherError<LeftReloadError, RightReloadError>, EitherError<LeftActionError, RightActionError>>] = right.map {
        TaggedEffect<EitherError<LeftReloadError, RightReloadError>, EitherError<LeftActionError, RightActionError>>(
            source: .right,
            effect: $0.mapErrors(
                reload: { .right($0) },
                action: { .right($0) }
            )
        )
    }

    return leftEffects + rightEffects
}

public enum EitherError<Left, Right> {
    case left(Left)
    case right(Right)
}

extension EitherError: Equatable where Left: Equatable, Right: Equatable {}
extension EitherError: Sendable where Left: Sendable, Right: Sendable {}

public extension AsyncContentEffect {
    func mapErrors<NewReloadError, NewActionError>(
        reload: (ReloadError) -> NewReloadError,
        action: (ActionError) -> NewActionError
    ) -> AsyncContentEffect<NewReloadError, NewActionError> {
        switch self {
        case let .reloadFailed(id, error):
            return .reloadFailed(id: id, error: reload(error))
        case let .actionFailed(id, error):
            return .actionFailed(id: id, error: action(error))
        }
    }
}

private func unionActivity(_ left: AsyncContentActivity, _ right: AsyncContentActivity) -> AsyncContentActivity {
    let hasReload = left.isReloading || right.isReloading
    let hasAction = left.isPerformingAction || right.isPerformingAction

    switch (hasReload, hasAction) {
    case (false, false):
        return .none
    case (true, false):
        return .reloading
    case (false, true):
        return .performingAction
    case (true, true):
        return .reloadingAndPerformingAction
    }
}
