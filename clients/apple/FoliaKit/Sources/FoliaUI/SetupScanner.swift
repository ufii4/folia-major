#if os(iOS)
import SwiftUI
import VisionKit

/// Camera QR scanner for the server's /pair page. Typing a 48-char token on
/// a phone keyboard is not a setup flow; this is.
struct SetupScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var fired = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in added {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    fired = true
                    scanner.stopScanning()
                    onFound(payload)
                    return
                }
            }
        }
    }
}
#endif
