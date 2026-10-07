import SwiftUI
import UIKit

/// A photo that fits the screen and zooms with a pinch or a double tap, then pans. A `UIScrollView` does the
/// zooming, because SwiftUI has no zooming scroll view on iOS 18.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView(image: image, label: label)
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.show(image, label: label)
    }
}

/// Fits the image at zoom 1, keeps it centred while zoomed out, and zooms up to the image's own pixels
/// (at least 4x).
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedBounds: CGSize = .zero

    init(image: UIImage, label: String) {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        show(image, label: label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ image: UIImage, label: String) {
        imageView.accessibilityLabel = label
        guard imageView.image !== image else { return }
        imageView.image = image
        fittedBounds = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let refit = bounds.size != fittedBounds
        if refit { fit() }
        centre()
        // A fresh fit starts at the top left of the centred image, not where the old zoom left the offset.
        if refit { contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top) }
    }

    /// Zoom 1 shows the whole image; a rotation or a new image fits it again.
    private func fit() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        fittedBounds = bounds.size
        zoomScale = 1
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        minimumZoomScale = 1
        let pixels = image.size.width * image.scale
        maximumZoomScale = max(4, pixels / max(size.width * traitCollection.displayScale, 1))
    }

    /// Insets that keep a smaller-than-the-screen image in the middle.
    private func centre() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = min(maximumZoomScale, 2.5)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }
}
