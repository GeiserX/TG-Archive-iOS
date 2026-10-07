import SwiftUI

/// A shared contact: the name and the phone number from `raw_data.contact`.
struct ContactCell: View {
    let contact: Contact?
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    private var name: String {
        let parts = [contact?.firstName?.nonBlank, contact?.lastName?.nonBlank].compactMap(\.self)
        return parts.isEmpty ? String(localized: "preview.kind.contact") : parts.joined(separator: " ")
    }

    /// Telegram keeps international numbers without the plus.
    static func phone(_ number: String?) -> String? {
        guard let number = number?.nonBlank else { return nil }
        return number.allSatisfy(\.isNumber) ? "+\(number)" : number
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.semibold))
                if let phone = Self.phone(contact?.phoneNumber) {
                    Text(verbatim: phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 180, maxWidth: MediaFrame.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
