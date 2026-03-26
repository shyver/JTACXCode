import SwiftUI

/// UIKit-level scroll helpers to work around gesture-recognition conflicts inside SwiftUI
/// `Form`/`List` when complex rows (pickers, buttons, text editors) cause delayed scrolling.
///
/// Attach using `.background(ScrollViewPanFix())` on a `Form`/`List`.
struct ScrollViewPanFix: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            attachFix(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            attachFix(from: uiView)
        }
    }

    private func attachFix(from view: UIView) {
        guard let scrollView = view.enclosingScrollView else { return }

        // Ensure pan starts immediately.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        // If we can find the internal wrapper view, also disable its touch delay.
        for sub in scrollView.subviews {
            if let wrapper = sub as? UIScrollView {
                wrapper.delaysContentTouches = false
                wrapper.canCancelContentTouches = true
            }
        }

        // In case a gesture recognizer is configured to wait, make scroll view pan win.
        // Avoid forcing failure of other gestures; only ensure simultaneous recognition.
        scrollView.panGestureRecognizer.cancelsTouchesInView = true
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var v: UIView? = self
        while let current = v {
            if let scroll = current as? UIScrollView { return scroll }
            v = current.superview
        }
        return nil
    }
}
