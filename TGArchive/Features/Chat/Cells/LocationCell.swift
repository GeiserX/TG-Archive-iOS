import MapKit
import SwiftUI

/// A location, a venue or a live location, drawn the same way for the three: the map picture the archive kept
/// with a marker at its centre, else a still MapKit map with a marker at the point, else a tile saying why
/// there is no map. Under it the venue's name and address, or the coordinates, and "Open in Maps" when there
/// is a point. Tapping opens Apple Maps at the point.
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
                } else if let coordinates = content.coordinates {
                    Text(verbatim: coordinates)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if content.mapsURL != nil {
                    Label("chat.location.openInMaps", systemImage: "arrow.up.forward.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
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
                // The server's map picture is centred on the point.
                image.resizable().scaledToFill()
                    .overlay { MapPin() }
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
                Image(systemName: "mappin.slash")
                    .font(.title2)
                Text(verbatim: content.unavailableText ?? String(localized: "preview.kind.location"))
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
        let detail = content.address ?? content.coordinates ?? content.unavailableText
        return Text(verbatim: [kind, content.title, detail].compactMap(\.self).joined(separator: ", "))
    }
}

/// The marker drawn on a map picture, shaped like MapKit's: a red balloon whose tip sits on the centre.
private struct MapPin: View {
    var body: some View {
        VStack(spacing: -4) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        // Lift the pin so its tip, not its middle, marks the point.
        .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
        .accessibilityHidden(true)
    }
}
