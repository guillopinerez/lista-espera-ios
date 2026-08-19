import Foundation
import AVFoundation
import UserNotifications
import AudioToolbox
import UIKit

@MainActor
class BackgroundSyncEngine: NSObject, ObservableObject {
    static let shared = BackgroundSyncEngine()

    @Published var contacts: [ClientContact] = []
    @Published var activeLines: [String] = ["TODAS", "EMILIA", "RAFAELLA", "NATALIA", "PEDRO TECNICO", "CARLOS"]
    @Published var selectedLine: String = "TODAS"
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date = Date()
    @Published var serverStatus: String = "🟢 Conectado"
    @Published var unreadTotal: Int = 0

    private var audioPlayer: AVAudioPlayer?
    private var syncTimer: Timer?
    private var lastSeenEventId: String = ""
    private var isInitialLoad: Bool = true
    private let serverUrl = "https://hotlatina4u.com/sms2/api.php"
    private let apiToken = "SAq1w2e3r4"

    override init() {
        super.init()
        setupAudioKeepAlive()
        startBackgroundSync()
    }

    // 1. Audio Keep-Alive Silencioso (Permite ejecución 24/7 con pantalla bloqueada)
    private func setupAudioKeepAlive() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let silentWavData = createSilentWavData()
            audioPlayer = try AVAudioPlayer(data: silentWavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.01
            audioPlayer?.play()
            print("🔊 Audio Keep-Alive en segundo plano activado")
        } catch {
            print("Error iniciando audio keep-alive: \(error)")
        }
    }

    // 2. Sincronización continua cada 2.5 segundos
    func startBackgroundSync() {
        syncTimer?.invalidate()
        fetchLatestData()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.fetchLatestData()
            }
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    // 3. Consulta de Eventos, Cola y Contactos al Servidor
    func fetchLatestData() {
        guard let url = URL(string: "\(serverUrl)?action=get_events&token=\(apiToken)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    BackgroundSyncEngine.shared.serverStatus = "🔴 Sin conexión"
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        BackgroundSyncEngine.shared.serverStatus = "🟢 En vivo"
                        BackgroundSyncEngine.shared.lastSyncTime = Date()
                        BackgroundSyncEngine.shared.processServerPayload(json)
                    }
                }
            } catch {
                print("Error decodificando eventos: \(error)")
            }
        }.resume()
    }

    // 4. Procesamiento Integral de Contactos y Detección de Nuevos Eventos
    func processServerPayload(_ json: [String: Any]) {
        // A. Cargar lista de contactos históricos y actuales
        var parsedContacts: [ClientContact] = []
        let rawContacts = json["contacts"] as? [[String: Any]] ?? []
        let queueItems = json["queue"] as? [[String: Any]] ?? []

        for c in rawContacts {
            let phone = String(describing: c["raw_phone"] ?? c["clean_phone"] ?? "")
            if phone.isEmpty { continue }

            let clientName = c["client_name"] as? String
            let lastMsg = String(describing: c["latest_message"] ?? "")
            let line = String(describing: c["line_name"] ?? c["line_key"] ?? "GENERAL")
            let ts = (c["latest_timestamp"] as? Double) ?? (Double(c["latest_timestamp"] as? Int ?? 0))

            // Determinar estado de cola
            var qStatus = "waiting"
            let cleanP = String(describing: c["clean_phone"] ?? "")
            if let matchingQueue = queueItems.first(where: {
                let qPhone = String(describing: $0["clean_phone"] ?? $0["phone"] ?? "")
                return qPhone == cleanP || qPhone == phone
            }) {
                qStatus = String(describing: matchingQueue["status"] ?? "waiting")
            }

            let contact = ClientContact(
                phone: phone,
                displayName: clientName,
                lastMessage: lastMsg,
                lastLine: line,
                lastTimestamp: ts > 0 ? ts : Date().timeIntervalSince1970,
                queueStatus: qStatus,
                waitingSince: ts,
                unreadCount: 1
            )
            parsedContacts.append(contact)
        }

        if !parsedContacts.isEmpty {
            self.contacts = parsedContacts
            self.unreadTotal = parsedContacts.filter({ $0.queueStatus == "waiting" }).count
        }

        // B. Comprobar eventos recientes para disparar Notificaciones Push
        let recentEvents = json["recent_events"] as? [[String: Any]] ?? []
        if let topEvent = recentEvents.first {
            let evId = String(describing: topEvent["id"] ?? "")
            let evPhone = String(describing: topEvent["raw_phone"] ?? topEvent["clean_phone"] ?? "")
            let evMsg = String(describing: topEvent["message"] ?? "")
            let evLine = String(describing: topEvent["line_key"] ?? topEvent["device_model"] ?? "GENERAL")

            if isInitialLoad {
                // En el primer arranque, registrar el ID actual como base sin disparar alerta
                lastSeenEventId = evId
                isInitialLoad = false
            } else if !evId.isEmpty && evId != lastSeenEventId && !evMsg.isEmpty {
                // 🔔 ¡NUEVO MENSAJE SMS RECIBIDO! Disparar Notificación de iOS
                lastSeenEventId = evId
                triggerPushNotification(phone: evPhone, message: evMsg, line: evLine)
            }
        }
    }

    // 5. Emisión de Notificación Local de iOS
    func triggerPushNotification(phone: String, message: String, line: String) {
        let content = UNMutableNotificationContent()
        content.title = "📱 Nuevo SMS [\(line.uppercased())]"
        content.subtitle = phone
        content.body = message
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: self.unreadTotal + 1)
        content.userInfo = ["phone": phone, "line": line]

        // Sonido y vibración háptica
        AudioServicesPlaySystemSound(1007)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // Entrega inmediata (trigger: nil)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error mostrando notificación: \(error)")
            } else {
                print("✅ Notificación despachada con éxito para \(phone)")
            }
        }
    }

    // Disparar Notificación de Prueba Manual
    func triggerTestNotification() {
        triggerPushNotification(
            phone: "+1 (555) 123-4567",
            message: "¡Prueba de Notificación Exitosa! La app está lista para recibir mensajes.",
            line: "PRUEBA"
        )
    }

    // Helper: Generador de WAV Silencioso
    private func createSilentWavData() -> Data {
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        var chunkSize: UInt32 = 36 + 8000 * 2
        withUnsafeBytes(of: &chunkSize) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WAVEfmt ".utf8)
        var sub1: UInt32 = 16
        withUnsafeBytes(of: &sub1) { data.append(contentsOf: $0) }
        var fmt: UInt16 = 1
        withUnsafeBytes(of: &fmt) { data.append(contentsOf: $0) }
        var channels: UInt16 = 1
        withUnsafeBytes(of: &channels) { data.append(contentsOf: $0) }
        var sampleRate: UInt32 = 8000
        withUnsafeBytes(of: &sampleRate) { data.append(contentsOf: $0) }
        var byteRate: UInt32 = 16000
        withUnsafeBytes(of: &byteRate) { data.append(contentsOf: $0) }
        var blockAlign: UInt16 = 2
        withUnsafeBytes(of: &blockAlign) { data.append(contentsOf: $0) }
        var bps: UInt16 = 16
        withUnsafeBytes(of: &bps) { data.append(contentsOf: $0) }
        data.append(contentsOf: "data".utf8)
        var sub2: UInt32 = 16000
        withUnsafeBytes(of: &sub2) { data.append(contentsOf: $0) }
        data.append(Data(repeating: 0, count: 16000))
        return data
    }
}
