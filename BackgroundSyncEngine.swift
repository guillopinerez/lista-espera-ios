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

            // Generar buffer de audio silencioso en memoria (1 segundo WAV inaudible en loop infinito)
            let silentWavData = createSilentWavData()
            audioPlayer = try AVAudioPlayer(data: silentWavData)
            audioPlayer?.numberOfLoops = -1 // Loop infinito
            audioPlayer?.volume = 0.01 // Inaudible pero activo para el hardware de audio
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

    // 3. Consulta de Eventos y Cola al Servidor
    func fetchLatestData() {
        guard let url = URL(string: "\(serverUrl)?action=get_events&limit=25&token=\(apiToken)") else { return }

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
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let events = json["events"] as? [[String: Any]] {

                    DispatchQueue.main.async {
                        BackgroundSyncEngine.shared.serverStatus = "🟢 En vivo"
                        BackgroundSyncEngine.shared.lastSyncTime = Date()
                        BackgroundSyncEngine.shared.processIncomingEvents(events)
                    }
                }
            } catch {
                print("Error decodificando eventos: \(error)")
            }
        }.resume()
    }

    // 4. Procesamiento de Eventos y Despacho de Notificaciones
    func processIncomingEvents(_ events: [[String: Any]]) {
        guard let latest = events.first else { return }

        let latestId = String(describing: latest["id"] ?? "")
        let phone = String(describing: latest["phone"] ?? "")
        let message = String(describing: latest["message"] ?? "")
        let line = String(describing: latest["line_key"] ?? latest["device_model"] ?? "GENERAL")
        let timestamp = latest["timestamp"] as? Double ?? Date().timeIntervalSince1970

        // Si es un evento nuevo y no es la primera carga inicial
        if !lastSeenEventId.isEmpty && latestId != lastSeenEventId && !message.isEmpty {
            // Disparar Notificación de iOS
            triggerPushNotification(phone: phone, message: message, line: line)
        }

        self.lastSeenEventId = latestId

        // Actualizar la lista local de contactos/clientes
        var updatedContacts = self.contacts
        let clientIndex = updatedContacts.firstIndex(where: { $0.phone == phone })

        if let idx = clientIndex {
            updatedContacts[idx].lastMessage = message
            updatedContacts[idx].lastLine = line
            updatedContacts[idx].lastTimestamp = timestamp
            // Mover al principio
            let item = updatedContacts.remove(at: idx)
            updatedContacts.insert(item, at: 0)
        } else {
            let newContact = ClientContact(
                phone: phone,
                displayName: nil,
                lastMessage: message,
                lastLine: line,
                lastTimestamp: timestamp,
                queueStatus: "waiting",
                waitingSince: timestamp,
                unreadCount: 1
            )
            updatedContacts.insert(newContact, at: 0)
        }

        self.contacts = updatedContacts
        self.unreadTotal = self.contacts.filter({ $0.queueStatus == "waiting" }).count
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
