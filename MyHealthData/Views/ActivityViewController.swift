#if canImport(UIKit)
import UIKit
import SwiftUI

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit
import SwiftUI

struct ActivityViewController: NSViewControllerRepresentable {
    let items: [Any]

    func makeNSViewController(context: Context) -> NSViewController {
        let vc = NSViewController()
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            if let v = vc.view {
                picker.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            }
        }
        return vc
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#endif
