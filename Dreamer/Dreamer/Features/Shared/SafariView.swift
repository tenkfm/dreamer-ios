import SafariServices
import SwiftUI

/// A page of dreamerapp.io inside the app (a Home card's article): Safari's reader, its own Done
/// button, and the user stays in Dreamer.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
