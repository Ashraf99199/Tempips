import SwiftUI
import WebKit

struct MessageDetailView: View {
    let summary: MessageSummary
    let vm: InboxViewModel

    @State private var detail: MessageDetail?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.subject.isEmpty ? "(بدون عنوان)" : summary.subject)
                    .font(.title3.bold())
                Text("من: \(summary.from.display)")
                    .font(.subheadline)
                Text(summary.from.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding()

            Divider()

            if let detail {
                if let html = detail.html?.joined(), !html.isEmpty {
                    HTMLView(html: html)
                } else {
                    ScrollView {
                        Text(detail.text ?? "")
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            } else if let error {
                ContentUnavailableView("ما قدرت أفتح الرسالة",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await vm.loadMessage(summary.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// يعرض محتوى HTML للرسالة، والروابط تفتح في Safari.
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // نوقف الجافاسكربت لأن الرسائل جاية من مصادر مجهولة
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let page = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font-family:-apple-system;padding:12px;word-wrap:break-word}img{max-width:100%;height:auto}</style>
        </head><body>\(html)</body></html>
        """
        view.loadHTMLString(page, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
