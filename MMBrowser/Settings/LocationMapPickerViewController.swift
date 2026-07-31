import MapKit
import UIKit

/// Modal map sheet for choosing custom spoof coordinates.
final class LocationMapPickerViewController: UIViewController, MKMapViewDelegate {
    var initialCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    var onPick: ((CLLocationCoordinate2D) -> Void)?

    private let mapView = MKMapView()
    private let coordinateLabel = UILabel()
    private let pin = MKPointAnnotation()
    private var selected = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Choose on Map"
        BrowserTheme.applyScreenChrome(to: self)
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        selected = initialCoordinate
        pin.coordinate = selected

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )

        mapView.delegate = self
        mapView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = false
        mapView.addAnnotation(pin)
        mapView.setRegion(
            MKCoordinateRegion(center: selected, latitudinalMeters: 80_000, longitudinalMeters: 80_000),
            animated: false
        )
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        mapView.addGestureRecognizer(tap)

        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        coordinateLabel.textColor = BrowserTheme.textPrimary
        coordinateLabel.textAlignment = .center
        coordinateLabel.numberOfLines = 2
        updateCoordinateLabel()

        let bar = UIView()
        bar.backgroundColor = BrowserTheme.card
        let hint = UILabel()
        hint.text = "Tap the map to place the pin"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = BrowserTheme.textSecondary
        hint.textAlignment = .center

        let enterManually = UIButton(type: .system)
        enterManually.setTitle("Enter Manually…", for: .normal)
        enterManually.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        enterManually.tintColor = BrowserTheme.chromeBlue
        enterManually.addTarget(self, action: #selector(enterManuallyTapped), for: .touchUpInside)

        view.addSubview(mapView)
        view.addSubview(bar)
        bar.addSubview(coordinateLabel)
        bar.addSubview(hint)
        bar.addSubview(enterManually)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        coordinateLabel.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false
        enterManually.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            coordinateLabel.topAnchor.constraint(equalTo: bar.topAnchor, constant: 14),
            coordinateLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            coordinateLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),

            hint.topAnchor.constraint(equalTo: coordinateLabel.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),

            enterManually.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            enterManually.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            enterManually.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
        let id = "spoof.pin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.markerTintColor = BrowserTheme.chromeBlue
        view.isDraggable = true
        view.canShowCallout = false
        return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        if newState == .ending || newState == .none {
            selected = view.annotation?.coordinate ?? selected
            pin.coordinate = selected
            updateCoordinateLabel()
        }
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: mapView)
        selected = mapView.convert(point, toCoordinateFrom: mapView)
        pin.coordinate = selected
        updateCoordinateLabel()
    }

    private func updateCoordinateLabel() {
        coordinateLabel.text = String(format: "Lat %.5f\nLon %.5f", selected.latitude, selected.longitude)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        onPick?(selected)
        dismiss(animated: true)
    }

    @objc private func enterManuallyTapped() {
        let alert = UIAlertController(title: "Custom Coordinates", message: "Latitude and longitude (decimal degrees).", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "Latitude"
            $0.keyboardType = .numbersAndPunctuation
            $0.text = String(format: "%.5f", self.selected.latitude)
        }
        alert.addTextField {
            $0.placeholder = "Longitude"
            $0.keyboardType = .numbersAndPunctuation
            $0.text = String(format: "%.5f", self.selected.longitude)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self = self,
                  let latText = alert.textFields?[0].text, let lonText = alert.textFields?[1].text,
                  let lat = Double(latText), let lon = Double(lonText),
                  lat >= -90, lat <= 90, lon >= -180, lon <= 180 else {
                if let self = self {
                    Toast.show("Invalid coordinates", from: self)
                }
                return
            }
            self.selected = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.pin.coordinate = self.selected
            self.mapView.setCenter(self.selected, animated: true)
            self.updateCoordinateLabel()
        })
        present(alert, animated: true)
    }
}
