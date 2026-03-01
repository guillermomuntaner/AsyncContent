#if canImport(Observation)
import Combine
import Foundation
import Observation
import AsyncContentAsync
import AsyncContentCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class ObservableAsyncContentStore<
    Value: Sendable,
    InitialError: Error & Sendable,
    ReloadError: Error & Sendable,
    ActionError: Error & Sendable
> {
    public private(set) var resource: AsyncContent<Value, InitialError>
    public private(set) var effects: [AsyncContentEffect<ReloadError, ActionError>]

    private let base: AsyncContentStore<Value, InitialError, ReloadError, ActionError>
    private var cancellables: Set<AnyCancellable> = []

    public init(base: AsyncContentStore<Value, InitialError, ReloadError, ActionError>) {
        self.base = base
        self.resource = base.resource
        self.effects = base.effects

        bind()
    }

    public var isCurrentContentEmpty: Bool {
        base.isCurrentContentEmpty
    }

    public var nextEffect: AsyncContentEffect<ReloadError, ActionError>? {
        base.nextEffect
    }

    @discardableResult
    public func consumeNextEffect() -> AsyncContentEffect<ReloadError, ActionError>? {
        base.consumeNextEffect()
    }

    public func clearEffects() {
        base.clearEffects()
    }

    public func resetToInitial() {
        base.resetToInitial()
    }

    public func load(operation: @escaping AsyncContentStore<Value, InitialError, ReloadError, ActionError>.InitialOperation) {
        base.load(operation: operation)
    }

    public func reload(operation: @escaping AsyncContentStore<Value, InitialError, ReloadError, ActionError>.ReloadOperation) {
        base.reload(operation: operation)
    }

    public func performAction(operation: @escaping AsyncContentStore<Value, InitialError, ReloadError, ActionError>.ActionOperation) {
        base.performAction(operation: operation)
    }

    public func performAction(operation: @escaping AsyncContentStore<Value, InitialError, ReloadError, ActionError>.ValueActionOperation) {
        base.performAction(operation: operation)
    }

    @discardableResult
    public func retryInitial() -> Bool {
        base.retryInitial()
    }

    @discardableResult
    public func retryReload() -> Bool {
        base.retryReload()
    }

    public func cancelInitialLoad() {
        base.cancelInitialLoad()
    }

    public func cancelReload() {
        base.cancelReload()
    }

    public func cancelAction() {
        base.cancelAction()
    }

    private func bind() {
        base.$resource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.resource = $0
            }
            .store(in: &cancellables)

        base.$effects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.effects = $0
            }
            .store(in: &cancellables)
    }
}
#endif
