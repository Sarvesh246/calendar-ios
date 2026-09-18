import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await capture() }
  }

  func capture() async {
    var payload: [String: String] = [:]
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      extensionContext?.completeRequest(returningItems: nil)
      return
    }
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
          payload["kind"] = url.pathExtension.lowercased() == "ics" ? "ics" : "url"
          payload["url"] = url.absoluteString
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                  let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
          payload["kind"] = "text"
          payload["text"] = text
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
                  let url = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? URL {
          payload["kind"] = "pdf"
          payload["url"] = url.absoluteString
          payload["filename"] = url.lastPathComponent
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          payload["kind"] = "image"
        } else if provider.hasItemConformingToTypeIdentifier(UTType.calendarEvent.identifier) {
          payload["kind"] = "ics"
        }
      }
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let raw = String(data: data, encoding: .utf8) {
      UserDefaults(suiteName: "group.com.sarveshjagtap.datebook")?.set(raw, forKey: "datebook.inbox")
    }
    if let url = URL(string: "datebook://open?intent=inbox") {
      var responder: UIResponder? = self
      while let r = responder {
        if let app = r as? UIApplication {
          app.open(url)
          break
        }
        responder = r.next
      }
    }
    extensionContext?.completeRequest(returningItems: nil)
  }
}
