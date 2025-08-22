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
        v.onChange = onChange
        return v
    }
    func updateUIView(_ uiView: _WindowProbeView, context: Context) {}
}

/// ViewModifier that only adds a context menu when the view is actually in a window.
/// Also intentionally **avoids** the `preview:` variant which is what drives UIPreviewTarget.
private struct SafeContextMenuModifier<Menu: View>: ViewModifier {
    @State private var attached = false
    @ViewBuilder var menu: () -> Menu

    func body(content: Content) -> some View {
        Group {
            if attached {
                // No preview closure on purpose — that path is what hits UIPreviewTarget.
                content.contextMenu { menu() }
            } else {
                content
            }
        }
        .background(_InWindowObserver { attached = $0 })
    }
}

public extension View {
    /// Use this instead of `.contextMenu` anywhere in the editing/time-setting flows.
    func safeContextMenu<Menu: View>(@ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        modifier(SafeContextMenuModifier(menu: menu))
    }
}

#endif
