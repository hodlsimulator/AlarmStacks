//
//  SafeContextMenu.swift
//  AlarmStacks
//
//  Created by . . on 8/22/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

// UIKit probe that lets us know when a SwiftUI view is in a window.
private final class _WindowProbeView: UIView {
    var onChange: ((Bool) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onChange?(window != nil)
    }
}

private struct _InWindowObserver: UIViewRepresentable {
    let onChange: (Bool) -> Void
    func makeUIView(context: Context) -> _WindowProbeView {
        let v = _WindowProbeView(frame: .zero)
        v.isHidden = true
        v.isUserInteractionEnabled = false
        v.onChange = onChange
        return v
    }
    func updateUIView(_ uiView: _WindowProbeView, context: Context) {}
}

// MARK: - Deferred-action infra

private struct _SafeMenuDelayKey: EnvironmentKey {
    static let defaultValue: UInt64 = 200_000_000 // 0.2s default
}

extension EnvironmentValues {
    fileprivate var _safeMenuDelay: UInt64 {
        get { self[_SafeMenuDelayKey.self] }
        set { self[_SafeMenuDelayKey.self] = newValue }
    }
}

/// A button for use inside `safeContextMenu {}` that defers its action until
/// shortly after the menu has dismissed, avoiding presentation from a detached VC.
public struct SafeMenuButton<Label: View>: View {
    @Environment(\._safeMenuDelay) private var delayNs
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: () -> Label

    public init(role: ButtonRole? = nil,
                action: @escaping () -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        self.role = role
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(role: role) {
            Task { @MainActor in
                // Let the context menu fully dismiss and the source view reattach to a window.
                try? await Task.sleep(nanoseconds: delayNs)
                action()
            }
        } label: { label() }
    }
}

/// ViewModifier that only adds a context menu when the view is actually in a window,
/// and avoids the `preview:` variant (which drives UIPreviewTarget).
private struct SafeContextMenuModifier<Menu: View>: ViewModifier {
    @State private var attached = false
    let delay: TimeInterval
    @ViewBuilder var menu: () -> Menu

    func body(content: Content) -> some View {
        Group {
            if attached {
                // Intentionally no `preview:` closure to avoid targeted previews.
                content.contextMenu {
                    menu()
                        .environment(\._safeMenuDelay, UInt64(max(0, delay) * 1_000_000_000))
                }
            } else {
                content
            }
        }
        .background(_InWindowObserver { attached = $0 })
    }
}

public extension View {
    /// Use this instead of `.contextMenu` anywhere in the editing/time-setting flows.
    /// - Parameter delay: How long to defer actions inside the menu (via `SafeMenuButton`) after dismissal.
    func safeContextMenu<Menu: View>(delay: TimeInterval = 0.2,
                                     @ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        modifier(SafeContextMenuModifier(delay: delay, menu: menu))
    }
}

#else

// Non-UIKit builds: provide a no-op so call sites still compile (e.g. previews/other platforms).
public extension View {
    func safeContextMenu<Menu: View>(delay: TimeInterval = 0.2,
                                     @ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        self
    }
}

/// Stub so code using `SafeMenuButton` still compiles on non-UIKit platforms.
public struct SafeMenuButton<Label: View>: View {
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: () -> Label

    public init(role: ButtonRole? = nil,
                action: @escaping () -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        self.role = role
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(role: role, action: action, label: label)
    }
}

#endif
