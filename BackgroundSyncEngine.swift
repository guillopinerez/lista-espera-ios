import Foundation
import AVFoundation
import UserNotifications
import UIKit

@MainActor
class BackgroundSyncEngine: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
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
        setupNotifications()
        setupAudioKeepAlive()
        startBackgroundSync()
    }

    // 1. Configuración de Notificaciones Locales
    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                print("Permiso de notificaciones concedido: \(granted)")
            }
        }
    }

    // 2. Audio Keep-Alive Silencioso (Permite ejecución 24/7 con pantalla bloqueada)
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

    // 3. Sincronización continua cada 2.5 segundos
    func startBackgroundSync() {
        syncTimer?.invalidate()
        fetchLatestData()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchLatestData()
            }
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    // 4. Consulta de Eventos y Cola al Servidor
    func fetchLatestData() {
        guard let url = URL(string: "\(serverUrl)?action=get_events&limit=25&token=\(apiToken)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.serverStatus = "🔴 Sin conexión"
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let events = json["events"] as? [[String: Any]] {

                    DispatchQueue.main.async {
                        self.serverStatus = "🟢 En vivo"
                        self.lastSyncTime = Date()
                        self.processIncomingEvents(events)
                    }
                }
            } catch {
                print("Error decodificando eventos: \(error)")
            }
        }.resume()
    }

    // 5. Procesamiento de Eventos y Despacho de Notificaciones
    private func processIncomingEvents(_ events: [[String: Any]]) {
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
            
            // Vibración háptica
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }

        self.lastSeenEventId = latestId

        // Actualizar la lista local de contactos/clientes
        var updatedContacts = self.contacts
        var clientIndex = updatedContacts.firstIndex(where: { $0.phone == phone })

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

    // 6. Emisión de Notificación Local de iOS
    private func triggerPushNotification(phone: String, message: String, line: String) {
        let content = UNMutableNotificationContent()
        content.title = "📱 Nuevo SMS [\(line.uppercased())]"
        content.subtitle = phone
        content.body = message
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: self.unreadTotal + 1)
        content.userInfo = ["phone": phone, "line": line]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error mostrando notificación: \(error)")
            }
        }
    }

    // Helper: Generador de WAV Silencioso
    private func createSilentWavData() -> Data {
        var data = Data()
        // Header WAV PCM 8000Hz 16-bit Mono silencioso
        data.append(contentsOf: "RIFF".utf8)
        let chunkSize: UInt32 = 36 + 8000 * 2
        data.append(Data(from: chunkSize))
        data.append(contentsOf: "WAVEfmt ".utf8)
        let subchunk1Size: UInt32 = 16
        data.append(Data(from: subchunk1Size))
        let audioFormat: UInt16 = 1 // PCM
        data.append(Data(from: audioFormat))
        let numChannels: UInt16 = 1
        data.append(Data(from: numChannels))
        let sampleRate: UInt32 = 8000
        data.append(Data(from: sampleRate))
        let byteRate: UInt32 = 8000 * 2
        data.append(Data(from: byteRate))
        let blockAlign: UInt16 = 2
        data.append(Data(from: blockAlign))
        let bitsPerSample: UInt16 = 16
        data.append(Data(from: bitsPerSample))
        data.append(contentsOf: "data".utf8)
        let subchunk2Size: UInt32 = 8000 * 2
        data.append(Data(from: subchunk2Size))
        // Silencio (0x00)
        data.append(Data(repeating: 0, count: Int(subchunk2Size)))
        return data
    }

    // Presentar notificación incluso cuando la app está abierta en pantalla
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// Extensión para serializar enteros en Data
extension Data {
    init<T>(from value: T) {
        var val = value
        self = Swift.withUnsafeBytes(of: &val) { Data($0) }
    }
}
