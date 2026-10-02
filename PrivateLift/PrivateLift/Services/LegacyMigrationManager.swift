import Foundation
import WebKit
import SwiftData
import Combine

@MainActor
class LegacyMigrationManager: NSObject, WKNavigationDelegate, WKScriptMessageHandler, ObservableObject {
    @Published var isMigrating = false
    @Published var migrationError: String? = nil
    
    private var webView: WKWebView?
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
    }
    
    func startMigrationIfNeeded() {
        // Skip if already migrated or if we don't have legacy storage to check
        if UserDefaults.standard.bool(forKey: "hasMigratedWebData") {
            return
        }
        
        debugLog("Starting legacy web data migration...")
        isMigrating = true
        
        // 1. Initialize modern WebView Configuration
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "migrationBridge")
        config.userContentController = contentController
        
        // 2. Initialize offscreen WKWebView
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        
        // 3. Load flat HTML app to load Web sandbox data
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            debugLog("Migration Error: index.html not found in main app bundle.")
            completeMigration(success: false, error: "Legacy asset files missing.")
            return
        }
        
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // WebView finished loading local files, execute custom Javascript to extract IndexedDB + LocalStorage
        let migrationScript = """
        (function() {
            return new Promise((resolve, reject) => {
                const req = indexedDB.open("PrivateLiftLocalDB", 1);
                req.onerror = () => reject("Failed to open legacy database.");
                req.onsuccess = (e) => {
                    const db = e.target.result;
                    const settingsVal = localStorage.getItem("privatelift_settings");
                    const settings = settingsVal ? JSON.parse(settingsVal) : null;
                    
                    const payload = {
                        settings: settings,
                        sessions: []
                    };
                    
                    if (!db.objectStoreNames.contains("sessions") || !db.objectStoreNames.contains("sets")) {
                        // DB or stores don't exist yet (new install, no data to migrate)
                        resolve(payload);
                        return;
                    }
                    
                    const tx = db.transaction(["sessions", "sets"], "readonly");
                    const sessionsStore = tx.objectStore("sessions");
                    const setsStore = tx.objectStore("sets");
                    
                    const sessionsMap = {};
                    
                    sessionsStore.openCursor().onsuccess = (ev) => {
                        const cursor = ev.target.result;
                        if (cursor) {
                            sessionsMap[cursor.key] = {
                                date: cursor.key,
                                notes: cursor.value.notes || "",
                                sets: []
                            };
                            cursor.continue();
                        } else {
                            // All sessions loaded, load all sets
                            setsStore.openCursor().onsuccess = (ev2) => {
                                const cursor2 = ev2.target.result;
                                if (cursor2) {
                                    const set = cursor2.value;
                                    const sDate = set.sessionDate;
                                    if (sessionsMap[sDate]) {
                                        sessionsMap[sDate].sets.push({
                                            exercise: set.exercise,
                                            weight: parseFloat(set.weight) || 0,
                                            reps: parseInt(set.reps) || 0,
                                            rpe: parseFloat(set.rpe) || 10,
                                            set_type: set.set_type || "working"
                                        });
                                    }
                                    cursor2.continue();
                                } else {
                                    // Complete
                                    payload.sessions = Object.values(sessionsMap);
                                    resolve(payload);
                                }
                            };
                        }
                    };
                    
                    tx.onerror = () => reject("Transaction failed.");
                };
            });
        })()
        .then(payload => {
            window.webkit.messageHandlers.migrationBridge.postMessage(JSON.stringify(payload));
        })
        .catch(err => {
            window.webkit.messageHandlers.migrationBridge.postMessage(JSON.stringify({ error: err }));
        });
        """
        
        webView.evaluateJavaScript(migrationScript, completionHandler: nil)
    }
    
    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "migrationBridge", let body = message.body as? String else {
            completeMigration(success: false, error: "Invalid message payload.")
            return
        }
        
        do {
            let data = Data(body.utf8)
            
            // Check if JavaScript returned an error
            if let errorPayload = try? JSONDecoder().decode(LegacyErrorPayload.self, from: data) {
                completeMigration(success: false, error: errorPayload.error)
                return
            }
            
            let payload = try JSONDecoder().decode(LegacyBackupPayload.self, from: data)
            
            // 1. Ingest settings if they exist
            if let settings = payload.settings {
                let prefsFetch = FetchDescriptor<UserPreferences>()
                let existingPrefs = try modelContext.fetch(prefsFetch)
                let prefs = existingPrefs.first ?? UserPreferences()
                
                prefs.squatMax = settings.squatMax
                prefs.benchMax = settings.benchMax
                prefs.deadliftMax = settings.deadliftMax
                prefs.bodyWeight = settings.bodyWeight
                prefs.gender = settings.gender
                prefs.weightUnit = settings.weightUnit
                prefs.appleHealthEnabled = settings.appleHealthEnabled
                prefs.isOnboarded = true
                prefs.hasMigratedWebData = true
                
                if existingPrefs.isEmpty {
                    modelContext.insert(prefs)
                }
                
                // Seed custom exercises first if not seeded
                DatabaseSeeder.seedDataIfNeeded(context: modelContext)
                
                // Sync with custom exercises
                let exerciseFetch = FetchDescriptor<CustomExercise>()
                do {
                    let exercises = try modelContext.fetch(exerciseFetch)
                    if let squatExercise = exercises.first(where: { $0.name == "SQUAT" }) {
                        squatExercise.oneRepMax = settings.squatMax
                    }
                    if let benchExercise = exercises.first(where: { $0.name == "BENCH" }) {
                        benchExercise.oneRepMax = settings.benchMax
                    }
                    if let deadliftExercise = exercises.first(where: { $0.name == "DEADLIFT" }) {
                        deadliftExercise.oneRepMax = settings.deadliftMax
                    }
                } catch {
                    debugLog("Failed to sync exercises during migration: \(error)")
                }
            } else {
                // If there is no settings payload, it means this was a fresh install with no legacy data.
                // We will still mark it as migrated to skip further triggers.
                let prefsFetch = FetchDescriptor<UserPreferences>()
                if let prefs = try modelContext.fetch(prefsFetch).first {
                    prefs.hasMigratedWebData = true
                }
            }
            
            // 2. Ingest Sessions & Sets
            for sessionData in payload.sessions {
                let sDate = sessionData.date
                var sessionFetch = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.dateString == sDate })
                sessionFetch.fetchLimit = 1

                let existingSession = try modelContext.fetch(sessionFetch).first
                let session: WorkoutSession
                if let existing = existingSession {
                    session = existing
                    session.notes = sessionData.notes ?? ""
                } else {
                    session = WorkoutSession(dateString: sDate, notes: sessionData.notes ?? "")
                    modelContext.insert(session)
                }

                for setData in sessionData.sets {
                    let newSet = WorkoutSet(
                        exercise: setData.exercise,
                        weight: setData.weight,
                        reps: setData.reps,
                        rpe: setData.rpe,
                        setType: setData.set_type
                    )
                    newSet.session = session
                    modelContext.insert(newSet)
                }
            }
            
            try modelContext.save()
            completeMigration(success: true)
        } catch {
            debugLog("Failed to save legacy data inside SwiftData context: \(error)")
            completeMigration(success: false, error: "Failed to persist database models.")
        }
    }
    
    private func completeMigration(success: Bool, error: String? = nil) {
        isMigrating = false
        webView = nil // Deallocate WebView cleanly
        
        if success {
            UserDefaults.standard.set(true, forKey: "hasMigratedWebData")
            debugLog("Legacy web data migration completed successfully.")
        } else {
            migrationError = error
            debugLog("Legacy web data migration failed: \(error ?? "Unknown error")")
        }
    }
}

// MARK: - Legacy Decodable Payload Declarations
private struct LegacyErrorPayload: Decodable {
    let error: String
}

private struct LegacyBackupPayload: Decodable {
    let settings: LegacySettings?
    let sessions: [LegacySession]
}

private struct LegacySettings: Decodable {
    let squatMax: Double
    let benchMax: Double
    let deadliftMax: Double
    let bodyWeight: Double
    let gender: String
    let weightUnit: String
    let appleHealthEnabled: Bool
}

private struct LegacySession: Decodable {
    let date: String
    let notes: String?
    let sets: [LegacySet]
}

private struct LegacySet: Decodable {
    let exercise: String
    let weight: Double
    let reps: Int
    let rpe: Double
    let set_type: String
}
