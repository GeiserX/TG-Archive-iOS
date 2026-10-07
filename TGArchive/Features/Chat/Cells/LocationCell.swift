import MapKit
import SwiftUI

/// A location, a venue or a live location: the map picture the archive kept, else a still MapKit map with a
/// marker at the point, else a plain "Location" tile; the venue's name and address under it. Tapping opens
/// Apple Maps at the point.
struct LocationCell: View {
    let content: LocationContent
    let context: ThreadContext
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale

    private let height: CGFloat = 150

    var body: some View {
        Button {
            if let url = content.mapsURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                picture
                    .frame(width: MediaFrame.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if content.kind == .geoLive {
                    Label("preview.kind.liveLocation", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let title = content.title {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                }
                if let address = content.address {
                    Text(verbatim: address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: MediaFrame.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(content.mapsURL == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var picture: some View {
        if let picture = content.mapPicture, !context.noDownload {
            RemoteImage(endpoint: .media(ref: context.ref, key: picture.key),
                        maxPixelSize: Int((MediaFrame.width * displayScale).rounded(.up))) { image in
                image.resizable().scaledToFill()
            } placeholder: { failure in
                if failure == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } else { map }
            }
        } else {
            map
        }
    }

    @ViewBuilder
    private var map: some View {
        if content.hasPoint, let latitude = content.latitude, let longitude = content.longitude {
            let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            Map(initialPosition: .region(MKCoordinateRegion(center: point, latitudinalMeters: 600,
                                                            longitudinalMeters: 600)),
                interactionModes: []) {
                Marker(content.title ?? "", coordinate: point)
            }
            .allowsHitTesting(false)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                Text("preview.kind.location")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
        }
    }

    private var accessibilityText: Text {
        let kind: String = switch content.kind {
        case .venue: String(localized: "preview.kind.venue")
        case .geoLive: String(localized: "preview.kind.liveLocation")
        default: String(localized: "preview.kind.location")
        }
        return Text(verbatim: [kind, content.title, content.address].compactMap(\.self).joined(separator: ", "))
    }
}
