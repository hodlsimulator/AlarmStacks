//
//  View+KeyboardDismiss.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//
//  Dismiss the keyboard by tapping anywhere (including List/Form backgrounds)
//  without blocking buttons, toggles, NavigationLinks, etc.

import SwiftUI
#if canImport(UIKit)
import UIKit

public extension View {
    /// Tap anywhere to dismiss the keyboard.
    /// Safe for use on `List`, `Form`, sheets, and pushed views.
    func dismissKeyboardOnTapAnywhere() -> some View {
        modifier(_GlobalKeyboardDismissModifier())
    }
}

private struct _GlobalKeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(_WindowTapInstaller())
    }
}

/// Installs a UITapGestureRecognizer on the hosting window so taps anywhere
/// (outside text inputs) will dismiss the keyboard.
///
/// Why window-level?
/// - List/Form often consume taps before a child overlay/gesture sees them.
/// - Window-level recogniser receives touches from the entire subtree.
/// - `cancelsTouchesInView = false` so other controls still get their taps.
private struct _WindowTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InstallView {
        let v = InstallView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: InstallView, context: Context) {
        uiView.coordinator = context.coordinator
    }

    final class InstallView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window = window, let coordinator else { return }

            // Avoid duplicate installs
            let alreadyInstalled = window.gestureRecognizers?.contains { $0 is _KeyboardDismissTap } ?? false
            guard !alreadyInstalled else { return }

            let tap = _KeyboardDismissTap(target: coordinator, action: #selector(Coordinator.handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = coordinator
            window.addGestureRecognizer(tap)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        // Don’t trigger when tapping directly inside text inputs (caret placement etc.).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            var v: UIView? = touch.view
            while let current = v {
                if current is UITextField || current is UITextView {
                    return false
                }
                v = current.superview
            }
            return true
        }

        // Play nicely with scrolling and other gestures.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// Subclass only so it’s easy to locate/remove if ever needed.
private final class _KeyboardDismissTap: UITapGestureRecognizer {}

#endif
