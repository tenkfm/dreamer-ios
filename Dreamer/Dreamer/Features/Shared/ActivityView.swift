import SwiftUI
import UIKit

/// The system share sheet with a completion report (ShareLink has none), so a finished share can
/// be told from a cancelled one.
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: (UIActivity.ActivityType?, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            onComplete(activity, completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
