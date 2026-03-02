import Testing
import AsyncContent
@testable import AsyncContentDemo

struct AsyncContentDemoTests {
    @Test
    @MainActor
    func loadStartsInLoadingInitialPhase() async {
        let viewModel = DemoViewModel()

        viewModel.load()

        #expect(viewModel.store.resource.phase == .loadingInitial)

        try? await Task.sleep(for: .milliseconds(700))
        #expect(viewModel.store.resource.phase == .content(["Ava", "Liam", "Mia"]))
    }

    @Test
    @MainActor
    func loadPopulatesContent() async {
        let viewModel = DemoViewModel()

        viewModel.load()
        try? await Task.sleep(for: .milliseconds(700))

        switch viewModel.store.resource.phase {
        case let .content(users):
            #expect(users.count == 3)
        default:
            #expect(Bool(false), "Expected content after load")
        }
    }

    @Test
    @MainActor
    func failLoadSetsInitialError() async {
        let viewModel = DemoViewModel()

        viewModel.failLoad()
        try? await Task.sleep(for: .milliseconds(500))

        switch viewModel.store.resource.phase {
        case .failedInitial(.loadFailed):
            #expect(Bool(true))
        default:
            #expect(Bool(false), "Expected initial failure")
        }
    }

    @Test
    @MainActor
    func reloadUpdatesVisibleContent() async {
        let viewModel = DemoViewModel()

        viewModel.load()
        try? await Task.sleep(for: .milliseconds(700))

        viewModel.reload()
        #expect(viewModel.store.resource.activity.isReloading)
        try? await Task.sleep(for: .milliseconds(600))

        switch viewModel.store.resource.phase {
        case let .content(users):
            #expect(users.contains("Noah"))
        default:
            #expect(Bool(false), "Expected content after reload")
        }
    }

    @Test
    @MainActor
    func failActionEmitsOneShotEffect() async {
        let viewModel = DemoViewModel()
        viewModel.load()
        try? await Task.sleep(for: .milliseconds(700))

        viewModel.failAction()
        #expect(viewModel.store.resource.activity.isPerformingAction)
        try? await Task.sleep(for: .milliseconds(400))

        #expect(viewModel.store.nextEffect != nil)
        _ = viewModel.store.consumeNextEffect()
        #expect(viewModel.store.nextEffect == nil)
    }

    @Test
    @MainActor
    func makeEmptyEndsWithEmptyContent() async {
        let viewModel = DemoViewModel()

        viewModel.makeEmpty()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.store.isCurrentContentEmpty)
    }
}
