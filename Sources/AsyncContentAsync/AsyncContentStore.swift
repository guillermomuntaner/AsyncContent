import Combine
import Foundation
import AsyncContentCore

@MainActor
public final class AsyncContentStore<
    Value: Sendable,
    InitialError: Error & Sendable,
    ReloadError: Error & Sendable,
    ActionError: Error & Sendable
>: ObservableObject {
    public typealias InitialOperation = @Sendable () async -> Result<Value, InitialError>
    public typealias ReloadOperation = @Sendable () async -> Result<Value, ReloadError>
    public typealias ActionOperation = @Sendable () async -> Result<Void, ActionError>
    public typealias ValueActionOperation = @Sendable (Value) async -> Result<Value, ActionError>

    @Published public private(set) var resource: AsyncContent<Value, InitialError>
    @Published public private(set) var effects: [AsyncContentEffect<ReloadError, ActionError>] = []

    private let isEmpty: (Value) -> Bool

    private var initialTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    private var initialOperationID: UUID?
    private var reloadOperationID: UUID?
    private var actionOperationID: UUID?

    private var lastInitialOperation: InitialOperation?
    private var lastReloadOperation: ReloadOperation?

    public init(
        resource: AsyncContent<Value, InitialError> = .init(),
        isEmpty: @escaping (Value) -> Bool = { _ in false }
    ) {
        self.resource = resource
        self.isEmpty = isEmpty
    }

    deinit {
        initialTask?.cancel()
        reloadTask?.cancel()
        actionTask?.cancel()
    }

    public var isCurrentContentEmpty: Bool {
        resource.isContentEmpty(using: isEmpty)
    }

    public var nextEffect: AsyncContentEffect<ReloadError, ActionError>? {
        effects.first
    }

    @discardableResult
    public func consumeNextEffect() -> AsyncContentEffect<ReloadError, ActionError>? {
        guard !effects.isEmpty else {
            return nil
        }

        return effects.removeFirst()
    }

    public func clearEffects() {
        effects.removeAll(keepingCapacity: false)
    }

    public func resetToInitial() {
        cancelInitialLoad()
        cancelReload()
        cancelAction()
        resource.resetToInitial()
        clearEffects()
    }

    public func load(operation: @escaping InitialOperation) {
        lastInitialOperation = operation
        cancelInitialLoad()

        resource.startInitialLoad()
        let operationID = UUID()
        initialOperationID = operationID

        initialTask = Task { [weak self] in
            let result = await operation()
            self?.finishInitial(result: result, operationID: operationID)
        }
    }

    public func load(
        operation: @escaping @Sendable () async throws -> Value,
        mapError: @escaping @Sendable (Error) -> InitialError
    ) {
        load {
            do {
                return .success(try await operation())
            } catch {
                return .failure(mapError(error))
            }
        }
    }

    @discardableResult
    public func retryInitial() -> Bool {
        guard let operation = lastInitialOperation else {
            return false
        }

        load(operation: operation)
        return true
    }

    public func retryInitial(operation: @escaping InitialOperation) {
        load(operation: operation)
    }

    public func reload(operation: @escaping ReloadOperation) {
        lastReloadOperation = operation
        cancelReload()

        guard resource.startReload() else {
            return
        }

        let operationID = UUID()
        reloadOperationID = operationID

        reloadTask = Task { [weak self] in
            let result = await operation()
            self?.finishReload(result: result, operationID: operationID)
        }
    }

    public func reload(
        operation: @escaping @Sendable () async throws -> Value,
        mapError: @escaping @Sendable (Error) -> ReloadError
    ) {
        reload {
            do {
                return .success(try await operation())
            } catch {
                return .failure(mapError(error))
            }
        }
    }

    @discardableResult
    public func retryReload() -> Bool {
        guard let operation = lastReloadOperation else {
            return false
        }

        reload(operation: operation)
        return true
    }

    public func retryReload(operation: @escaping ReloadOperation) {
        reload(operation: operation)
    }

    public func performAction(operation: @escaping ActionOperation) {
        cancelAction()

        guard resource.startAction() else {
            return
        }

        let operationID = UUID()
        actionOperationID = operationID

        actionTask = Task { [weak self] in
            let result = await operation()
            self?.finishAction(result: result, operationID: operationID)
        }
    }

    public func performAction(
        operation: @escaping @Sendable () async throws -> Void,
        mapError: @escaping @Sendable (Error) -> ActionError
    ) {
        performAction {
            do {
                try await operation()
                return .success(())
            } catch {
                return .failure(mapError(error))
            }
        }
    }

    public func performAction(operation: @escaping ValueActionOperation) {
        cancelAction()

        guard resource.startAction(), let currentValue = resource.value else {
            return
        }

        let operationID = UUID()
        actionOperationID = operationID

        actionTask = Task { [weak self] in
            let result = await operation(currentValue)
            self?.finishValueAction(result: result, operationID: operationID)
        }
    }

    public func load(
        from callback: @escaping @Sendable (@escaping @Sendable (Result<Value, InitialError>) -> Void) -> Void
    ) {
        load {
            await withCheckedContinuation { continuation in
                callback { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    public func reload(
        from callback: @escaping @Sendable (@escaping @Sendable (Result<Value, ReloadError>) -> Void) -> Void
    ) {
        reload {
            await withCheckedContinuation { continuation in
                callback { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    public func performAction(
        from callback: @escaping @Sendable (@escaping @Sendable (Result<Void, ActionError>) -> Void) -> Void
    ) {
        performAction {
            await withCheckedContinuation { continuation in
                callback { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    public func cancelInitialLoad() {
        initialTask?.cancel()
        initialTask = nil
        initialOperationID = nil

        if case .loadingInitial = resource.phase {
            resource.phase = .initial
        }
    }

    public func cancelReload() {
        reloadTask?.cancel()
        reloadTask = nil
        reloadOperationID = nil
        resource.activity = resource.activity.settingReloading(false)
    }

    public func cancelAction() {
        actionTask?.cancel()
        actionTask = nil
        actionOperationID = nil
        resource.activity = resource.activity.settingPerformingAction(false)
    }

    private func emit(_ effect: AsyncContentEffect<ReloadError, ActionError>) {
        effects.append(effect)
    }

    private func finishInitial(result: Result<Value, InitialError>, operationID: UUID) {
        guard initialOperationID == operationID else {
            return
        }

        initialTask = nil
        initialOperationID = nil

        switch result {
        case let .success(value):
            resource.finishInitialSuccess(value)
        case let .failure(error):
            resource.finishInitialFailure(error)
        }
    }

    private func finishReload(result: Result<Value, ReloadError>, operationID: UUID) {
        guard reloadOperationID == operationID else {
            return
        }

        reloadTask = nil
        reloadOperationID = nil

        switch result {
        case let .success(value):
            _ = resource.finishReloadSuccess(value)
        case let .failure(error):
            if let rawEffect = resource.finishReloadFailure(error) {
                if case let .reloadFailed(id, reloadError) = rawEffect {
                    emit(.reloadFailed(id: id, error: reloadError))
                }
            }
        }
    }

    private func finishAction(result: Result<Void, ActionError>, operationID: UUID) {
        guard actionOperationID == operationID else {
            return
        }

        actionTask = nil
        actionOperationID = nil

        switch result {
        case .success:
            resource.finishActionSuccess()
        case let .failure(error):
            if let rawEffect = resource.finishActionFailure(error) {
                if case let .actionFailed(id, actionError) = rawEffect {
                    emit(.actionFailed(id: id, error: actionError))
                }
            }
        }
    }

    private func finishValueAction(result: Result<Value, ActionError>, operationID: UUID) {
        guard actionOperationID == operationID else {
            return
        }

        actionTask = nil
        actionOperationID = nil

        switch result {
        case let .success(updatedValue):
            resource.phase = .content(updatedValue)
            resource.finishActionSuccess()
        case let .failure(error):
            if let rawEffect = resource.finishActionFailure(error) {
                if case let .actionFailed(id, actionError) = rawEffect {
                    emit(.actionFailed(id: id, error: actionError))
                }
            }
        }
    }
}

public extension AsyncContentStore where Value: EmptyRepresentable {
    convenience init(resource: AsyncContent<Value, InitialError> = .init()) {
        self.init(resource: resource, isEmpty: { $0.isEmpty })
    }
}
