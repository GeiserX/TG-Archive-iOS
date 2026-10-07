import SwiftUI

/// One error sentence pinned to the top of a screen, with an optional Retry and an optional close button.
/// Every screen shows its errors this way: `.errorBanner(model.error, retry: { ... })`.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    var dismiss: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("banner.message")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button(action: retry) { Text("banner.retry") }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("banner.retry")
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .accessibilityLabel(Text("banner.dismiss"))
                }
                .accessibilityIdentifier("banner.dismiss")
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Shows `message` in a banner above the content; nothing when it is nil.
    func errorBanner(_ message: String?, retry: (() -> Void)? = nil, dismiss: (() -> Void)? = nil) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let message {
                ErrorBanner(message: message, retry: retry, dismiss: dismiss)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: message)
    }

    /// Shows an `APIError`'s sentence. A cancelled request is not an error worth showing.
    func errorBanner(_ error: APIError?, retry: (() -> Void)? = nil, dismiss: (() -> Void)? = nil) -> some View {
        errorBanner(error.flatMap { $0.isCancellation ? nil : $0.message }, retry: retry, dismiss: dismiss)
    }
}

#Preview {
    NavigationStack {
        List { Text(verbatim: "Content") }
            .errorBanner(APIError.transport(.notConnectedToInternet), retry: {})
    }
}
