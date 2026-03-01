import AsyncContentAsync
import AsyncContentCore
import SwiftUI

public extension AsyncContentStore {
    @MainActor
    func effectBinding() -> Binding<AsyncContentEffect<TransientError>?> {
        Binding(
            get: { self.nextEffect },
            set: { value in
                guard value == nil else {
                    return
                }

                _ = self.consumeNextEffect()
            }
        )
    }
}
