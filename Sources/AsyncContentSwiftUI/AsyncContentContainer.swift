import AsyncContentCore
import SwiftUI

public struct AsyncContentContainer<Value, InitialError, Content: View>: View {
    private let resource: AsyncContent<Value, InitialError>
    private let isEmpty: (Value) -> Bool
    private let contentBuilder: (Value) -> Content
    private let loadingBuilder: () -> AnyView
    private let initialErrorBuilder: (InitialError) -> AnyView
    private let emptyBuilder: () -> AnyView
    private let overlayBuilder: (AsyncContentActivity) -> AnyView?
    private let animation: Animation?

    public init<Loading: View, InitialErrorView: View, EmptyView: View, OverlayView: View>(
        resource: AsyncContent<Value, InitialError>,
        isEmpty: @escaping (Value) -> Bool,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder initialError: @escaping (InitialError) -> InitialErrorView,
        @ViewBuilder empty: @escaping () -> EmptyView,
        @ViewBuilder overlay: @escaping (AsyncContentActivity) -> OverlayView?
    ) {
        self.resource = resource
        self.isEmpty = isEmpty
        self.animation = animation
        self.contentBuilder = content
        self.loadingBuilder = { AnyView(loading()) }
        self.initialErrorBuilder = { AnyView(initialError($0)) }
        self.emptyBuilder = { AnyView(empty()) }
        self.overlayBuilder = { activity in
            overlay(activity).map { AnyView($0) }
        }
    }

    public init<InitialErrorView: View, EmptyView: View>(
        resource: AsyncContent<Value, InitialError>,
        isEmpty: @escaping (Value) -> Bool,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder initialError: @escaping (InitialError) -> InitialErrorView,
        @ViewBuilder empty: @escaping () -> EmptyView
    ) {
        self.resource = resource
        self.isEmpty = isEmpty
        self.animation = animation
        self.contentBuilder = content
        self.loadingBuilder = { AnyView(ProgressView()) }
        self.initialErrorBuilder = { AnyView(initialError($0)) }
        self.emptyBuilder = { AnyView(empty()) }
        self.overlayBuilder = { activity in
            guard activity != .none else {
                return nil
            }

            return AnyView(DefaultActivityOverlay())
        }
    }

    public var body: some View {
        Group {
            switch resource.phase {
            case .initial, .loadingInitial:
                loadingBuilder()
            case let .failedInitial(error):
                initialErrorBuilder(error)
            case let .content(value):
                ZStack {
                    if isEmpty(value) {
                        emptyBuilder()
                    } else {
                        contentBuilder(value)
                    }

                    if let overlay = overlayBuilder(resource.activity) {
                        overlay
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(animation, value: resource.phaseDescription)
        .animation(animation, value: resource.activity)
    }
}

public extension AsyncContentContainer where Value: EmptyRepresentable {
    init<Loading: View, InitialErrorView: View, EmptyView: View, OverlayView: View>(
        resource: AsyncContent<Value, InitialError>,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder initialError: @escaping (InitialError) -> InitialErrorView,
        @ViewBuilder empty: @escaping () -> EmptyView,
        @ViewBuilder overlay: @escaping (AsyncContentActivity) -> OverlayView?
    ) {
        self.init(
            resource: resource,
            isEmpty: { $0.isEmpty },
            animation: animation,
            content: content,
            loading: loading,
            initialError: initialError,
            empty: empty,
            overlay: overlay
        )
    }

    init<InitialErrorView: View, EmptyView: View>(
        resource: AsyncContent<Value, InitialError>,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder initialError: @escaping (InitialError) -> InitialErrorView,
        @ViewBuilder empty: @escaping () -> EmptyView
    ) {
        self.init(
            resource: resource,
            isEmpty: { $0.isEmpty },
            animation: animation,
            content: content,
            initialError: initialError,
            empty: empty
        )
    }
}

@available(iOS 17.0, macOS 14.0, *)
public extension AsyncContentContainer {
    init(
        resource: AsyncContent<Value, InitialError>,
        isEmpty: @escaping (Value) -> Bool,
        emptyPresentation: UnavailablePresentation,
        initialErrorPresentation: @escaping (InitialError) -> UnavailablePresentation,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.init(
            resource: resource,
            isEmpty: isEmpty,
            animation: animation,
            content: content,
            initialError: { error in
                UnavailableDefaultView(presentation: initialErrorPresentation(error))
            },
            empty: {
                UnavailableDefaultView(presentation: emptyPresentation)
            }
        )
    }
}

private struct DefaultActivityOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            ProgressView()
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("resource.activity.overlay")
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct UnavailableDefaultView: View {
    let presentation: UnavailablePresentation

    var body: some View {
        ContentUnavailableView(
            presentation.title,
            systemImage: presentation.systemImage,
            description: presentation.message.map(Text.init)
        )
    }
}

private extension AsyncContent {
    var phaseDescription: String {
        switch phase {
        case .initial:
            return "initial"
        case .loadingInitial:
            return "loadingInitial"
        case .content:
            return "content"
        case .failedInitial:
            return "failedInitial"
        }
    }
}
