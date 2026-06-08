// WatchConnectivityManager.swift (Watch target)
import Foundation
@preconcurrency import WatchConnectivity

/// Manages WatchConnectivity session on the watchOS side.
/// The actual data fetching lives on the iPhone — the Watch just sends requests.
final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnectivityManager()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("WatchConnectivityManager: activation failed – \(error.localizedDescription)")
        }
    }
}
