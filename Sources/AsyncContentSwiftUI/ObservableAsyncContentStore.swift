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
    BlockingError: Error & Sendable,
    TransientError: Error & Sendable
> {
    public private(set) var resource: AsyncContent<Value, BlockingError>
    public private(set) var effects: [AsyncContentEffect<TransientError>]

    private let base: AsyncContentStore<Value, BlockingError, TransientError>
    private var cancellables: Set<AnyCancellable> = []

    public init(base: AsyncContentStore<Value, BlockingError, TransientError>) {
        self.base = base
        self.resource = base.resource
        self.effects = base.effects

        bind()
    }

    public var isCurrentContentEmpty: Bool {
        base.isCurrentContentEmpty
    }

    public var nextEffect: AsyncContentEffect<TransientError>? {
        base.nextEffect
    }

    @discardableResult
    public func consumeNextEffect() -> AsyncContentEffect<TransientError>? {
        base.consumeNextEffect()
    }

    public func clearEffects() {
        base.clearEffects()
    }

    public func resetToInitial() {
        base.resetToInitial()
    }

    public func load(operation: @escaping AsyncContentStore<Value, BlockingError, TransientError>.InitialOperation) {
        base.load(operation: operation)
    }

    public func reload(operation: @escaping AsyncContentStore<Value, BlockingError, TransientError>.ReloadOperation) {
        base.reload(operation: operation)
    }

    public func performAction(operation: @escaping AsyncContentStore<Value, BlockingError, TransientError>.ActionOperation) {
        base.performAction(operation: operation)
    }

    public func performAction(operation: @escaping AsyncContentStore<Value, BlockingError, TransientError>.ValueActionOperation) {
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

@available(iOS 17.0, macOS 14.0, *)
public extension ObservableAsyncContentStore where TransientError == Never {
    func reload(operation: @escaping @Sendable () async -> Value) {
        base.reload(operation: operation)
    }

    func performAction(operation: @escaping @Sendable () async -> Void) {
        base.performAction(operation: operation)
    }

    func performAction(operation: @escaping @Sendable (Value) async -> Value) {
        base.performAction(operation: operation)
    }
}
#endif
