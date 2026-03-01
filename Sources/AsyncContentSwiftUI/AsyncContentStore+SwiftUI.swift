import AsyncContentAsync
import AsyncContentCore
import SwiftUI

public extension AsyncContentStore {
    @MainActor
    func effectBinding() -> Binding<AsyncContentEffect<ReloadError, ActionError>?> {
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
