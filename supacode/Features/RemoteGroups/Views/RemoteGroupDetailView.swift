import SwiftUI
import WebKit

struct RemoteGroupDetailView: View {
  let endpoint: RemoteEndpoint
  let group: String?

  private var resolvedURL: URL {
    if let group {
      return endpoint.groupURL(group: group)
    }
    return endpoint.overviewURL
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "network")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(endpoint.baseURL.absoluteString)
          .font(.footnote.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
        if let group {
          Text("group=\(group)")
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      RemoteGroupWebView(url: resolvedURL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct RemoteGroupWebView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero)
    webView.allowsBackForwardNavigationGestures = true
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    if nsView.url?.absoluteString != url.absoluteString {
      nsView.load(URLRequest(url: url))
    }
  }
}
