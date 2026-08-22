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
    private var failedAttempts: Int = 0
    private let serverUrl = "https://hotlatina4u.com/sms2/api.php"
    private let apiToken = "SAq1w2e3r4"

    private lazy var customSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    private var dispatchTimer: DispatchSourceTimer?
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        setupAudioKeepAlive()
        setupLifecycleObservers()
        startBackgroundSync()
    }

    // 1. Escuchadores de Ciclo de Vida e Interrupciones de Audio
    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAppForeground() {
        Task { @MainActor in
            self.failedAttempts = 0
            if self.bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTaskId)
                self.bgTaskId = .invalid
            }
            self.startBackgroundSync()
        }
    }

    @objc private func handleDidEnterBackground() {
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "ListaEsperaKeepAlive") { [weak self] in
            if let id = self?.bgTaskId, id != .invalid {
                UIApplication.shared.endBackgroundTask(id)
                self?.bgTaskId = .invalid
            }
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if self.audioPlayer?.isPlaying == false {
                self.audioPlayer?.play()
            }
        } catch {
            print("Error reactivando audio en segundo plano: \(error)")
        }
    }

    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                audioPlayer?.play()
            } catch {}
        }
    }

    // 2. Audio Keep-Alive Silencioso 24/7 (Playback dedicado sin suspension de iOS)
    private func setupAudioKeepAlive() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let silentWavData = createSilentWavData()
            audioPlayer = try AVAudioPlayer(data: silentWavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.05
            audioPlayer?.play()
            print("🔊 Audio Keep-Alive en segundo plano activado")
        } catch {
            print("Error iniciando audio keep-alive: \(error)")
        }
    }

    // 3. Sincronización continua de fondo con DispatchSourceTimer (inmune a congelamiento de UI Main Loop)
    func startBackgroundSync() {
        syncTimer?.invalidate()
        dispatchTimer?.cancel()
        fetchLatestData()

        // Timer de Main Loop para interfaz cuando la app está activa
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.fetchLatestData()
            }
        }
        RunLoop.main.add(syncTimer!, forMode: .common)

        // Timer de Hilo Secundario de Dispatch para segundo plano constante con pantalla bloqueada
        let queue = DispatchQueue(label: "com.amoravias.listadeespera.sync", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.5, repeating: .seconds(3), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.audioPlayer?.isPlaying == false {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.audioPlayer?.play()
            }
            self.fetchLatestData()
        }
        timer.resume()
        self.dispatchTimer = timer
    }

    // 4. Consulta de Eventos, Cola y Contactos al Servidor
    func fetchLatestData() {
        guard let url = URL(string: "\(serverUrl)?action=get_events&token=\(apiToken)&_=\(Date().timeIntervalSince1970)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        customSession.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.failedAttempts += 1
                    // Solo cambiar a Sin conexión tras 4 fallos consecutivos reales (evita pestañeos en iOS)
                    if (self?.failedAttempts ?? 0) >= 4 {
                        BackgroundSyncEngine.shared.serverStatus = "🔴 Sin conexión"
                    }
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        self?.failedAttempts = 0
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

    // 4. Procesamiento Integral de Contactos con Conversación Unificada y Detección de Nuevos Eventos
    func processServerPayload(_ json: [String: Any]) {
        // A. Cargar lista de contactos históricos y actuales
        var parsedContacts: [ClientContact] = []
        let rawContacts = json["contacts"] as? [[String: Any]] ?? []
        let queueItems = json["queue"] as? [[String: Any]] ?? []

        for c in rawContacts {
            let rawP = String(describing: c["raw_phone"] ?? c["clean_phone"] ?? "")
            let cleanP = String(describing: c["clean_phone"] ?? "")
            if cleanP.isEmpty && rawP.isEmpty { continue }

            let phone = rawP.isEmpty ? cleanP : rawP
            let clientName = c["client_name"] as? String
            let lastMsg = String(describing: c["latest_message"] ?? "")
            let line = String(describing: c["line_name"] ?? c["line_key"] ?? "GENERAL")
            let ts = (c["latest_timestamp"] as? Double) ?? (Double(c["latest_timestamp"] as? Int ?? 0))
            let atendido = c["atendido_por"] as? String
            let reqTime = c["detected_time"] as? String

            // Mensajes del día unificados (Conversación)
            var todayMsgs: [TodayMessage] = []
            if let rawToday = c["today_messages"] as? [[String: Any]] {
                for m in rawToday {
                    let mId = String(describing: m["id"] ?? UUID().uuidString)
                    let mMsg = String(describing: m["message"] ?? "")
                    let mDate = String(describing: m["date"] ?? "")
                    let mTs = (m["timestamp"] as? Double) ?? (Double(m["timestamp"] as? Int ?? 0))
                    let mLk = String(describing: m["line_key"] ?? line)
                    let mLn = String(describing: m["line_name"] ?? line)
                    let mIsToday = (m["is_today"] as? Bool) ?? true
                    todayMsgs.append(TodayMessage(id: mId, message: mMsg, date: mDate, timestamp: mTs, lineKey: mLk, lineName: mLn, isToday: mIsToday))
                }
            }

            // Perfil enriquecido completo
            var profData: ClientProfileData? = nil
            if let pDict = c["profile"] as? [String: Any] {
                let pFound = (pDict["found"] as? Bool) ?? false
                let pName = String(describing: pDict["primary_name"] ?? (clientName ?? "No es cliente registrado"))
                let pSvcCount = (pDict["service_count"] as? Int) ?? 0
                let pTotRev = (pDict["total_revenue"] as? Double) ?? (Double(pDict["total_revenue"] as? Int ?? 0))
                let pRev30 = (pDict["revenue_30_days"] as? Double) ?? (Double(pDict["revenue_30_days"] as? Int ?? 0))
                let pRank = (pDict["client_rank"] as? Int) ?? 1
                let pCounts = (pDict["counts"] as? [String: Int]) ?? [:]
                let pTechs = (pDict["technicians"] as? [String]) ?? []
                let pAtendidoStr = String(describing: pDict["atendido_por_str"] ?? (atendido ?? "Sin servicios previos"))
                
                var pTechsDetail: [TechnicianDetailItem] = []
                if let rawTechDetail = pDict["technicians_detail"] as? [[String: Any]] {
                    for td in rawTechDetail {
                        let tName = String(describing: td["tecnico"] ?? "")
                        let tFecha = String(describing: td["fecha"] ?? "")
                        let tTiempo = String(describing: td["tiempo"] ?? "")
                        let tLabel = String(describing: td["tiempo_label"] ?? tTiempo)
                        let tTarifa = td["tarifa"] as? String
                        let tDisp = String(describing: td["display"] ?? "\(tName) • \(tFecha) • \(tLabel)")
                        if !tName.isEmpty {
                            pTechsDetail.append(TechnicianDetailItem(tecnico: tName, fecha: tFecha, tiempo: tTiempo, tiempoLabel: tLabel, tarifa: tTarifa, display: tDisp))
                        }
                    }
                }

                var pComments: [ClientComment] = []
                if let rawComms = pDict["comments"] as? [[String: Any]] {
                    for comm in rawComms {
                        let cId = String(describing: comm["id"] ?? UUID().uuidString)
                        let cTxt = String(describing: comm["comentario"] ?? "")
                        let cDate = String(describing: comm["fecha_comentario"] ?? "")
                        pComments.append(ClientComment(id: cId, comentario: cTxt, fecha_comentario: cDate))
                    }
                }

                profData = ClientProfileData(
                    found: pFound,
                    primaryName: pName,
                    serviceCount: pSvcCount,
                    totalRevenue: pTotRev,
                    revenue30Days: pRev30,
                    clientRank: pRank,
                    counts: pCounts,
                    technicians: pTechs,
                    techniciansDetail: pTechsDetail,
                    atendidoPorStr: pAtendidoStr,
                    comments: pComments,
                    conversation: todayMsgs
                )
            }

            // Determinar estado de cola
            var qStatus = "waiting"
            if let matchingQueue = queueItems.first(where: {
                let qPhone = String(describing: $0["clean_phone"] ?? $0["phone"] ?? "")
                return qPhone == cleanP || qPhone == phone
            }) {
                qStatus = String(describing: matchingQueue["status"] ?? "waiting")
            }

            let contact = ClientContact(
                cleanPhone: cleanP,
                phone: phone,
                displayName: clientName,
                atendidoPor: atendido,
                technicians: profData?.technicians ?? [],
                techniciansDetail: profData?.techniciansDetail ?? [],
                lastMessage: lastMsg,
                lastLine: line,
                lastTimestamp: ts > 0 ? ts : Date().timeIntervalSince1970,
                detectedTime: reqTime,
                queueStatus: qStatus,
                waitingSince: ts,
                unreadCount: 1,
                todayMessages: todayMsgs,
                profile: profData
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
            
            // Buscar perfil del cliente para el nombre de la notificación
            let evProf = topEvent["profile"] as? [String: Any]
            let evName = evProf?["primary_name"] as? String
            let evFound = (evProf?["found"] as? Bool) ?? false

            if isInitialLoad {
                lastSeenEventId = evId
                isInitialLoad = false
            } else if !evId.isEmpty && evId != lastSeenEventId && !evMsg.isEmpty {
                // 🔔 ¡NUEVO MENSAJE SMS RECIBIDO! Disparar Notificación de iOS
                lastSeenEventId = evId
                triggerPushNotification(phone: evPhone, message: evMsg, line: evLine, clientName: evName, isClient: evFound)
            }
        }
    }

    // 5. Emisión de Notificación de iOS con Formato Profesional y Sonidos Ultracortos por Perfil
    func triggerPushNotification(phone: String, message: String, line: String, clientName: String? = nil, isClient: Bool = false) {
        let content = UNMutableNotificationContent()
        
        let isRegistered = isClient || (clientName != nil && !clientName!.isEmpty && clientName != "No es cliente registrado" && clientName != "NO ES CLIENTE")

        if isRegistered {
            let nameTxt = clientName ?? "CLIENTE REGISTRADO"
            content.title = "🌟 CLIENTE: \(nameTxt.uppercased())"
            AudioServicesPlaySystemSound(1057) // 🌟 SystemSoundID 1057: Tink / Cristalino Ultracorto (~0.18s)
        } else {
            content.title = "📱 SMS NUEVO [\(line.uppercased())]"
            AudioServicesPlaySystemSound(1104) // 📱 SystemSoundID 1104: Tock / Pop Corto (~0.12s)
        }

        // 2. SUBTÍTULO: Línea receptora y Teléfono
        content.subtitle = "📱 Línea: \(line.uppercased()) • \(phone)"

        // 3. CUERPO: Mensaje SMS recibido
        content.body = "\"\(message)\""
        
        content.badge = NSNumber(value: self.unreadTotal + 1)
        content.userInfo = ["phone": phone, "line": line, "is_client": isRegistered]

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
                print("✅ Notificación despachada: [\(content.title)] Línea: \(line)")
            }
        }
    }

    // Disparar Notificación de Prueba Manual
    func triggerTestNotification() {
        triggerPushNotification(
            phone: "+1 (732) 207-7581",
            message: "Room No. ?? Are you there?",
            line: "NATALIA",
            clientName: "CHAN / CARLOS",
            isClient: true
        )
    }

    // Consultar Perfil Enriquecido Individual del Cliente (con Ranking Histórico y Notas)
    func fetchClientProfile(phone: String, completion: @escaping (ClientProfileData?) -> Void) {
        let clean = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard let url = URL(string: "\(serverUrl)?action=get_client&telefono=\(clean)&token=\(apiToken)&_=" + String(Date().timeIntervalSince1970)) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pDict = json["profile"] as? [String: Any] {
                    let pFound = (pDict["found"] as? Bool) ?? false
                    let pName = String(describing: pDict["primary_name"] ?? "No es cliente registrado")
                    let pSvcCount = (pDict["service_count"] as? Int) ?? 0
                    let pTotRev = (pDict["total_revenue"] as? Double) ?? (Double(pDict["total_revenue"] as? Int ?? 0))
                    let pRev30 = (pDict["revenue_30_days"] as? Double) ?? (Double(pDict["revenue_30_days"] as? Int ?? 0))
                    let pRank = (pDict["client_rank"] as? Int) ?? 1
                    let pCounts = (pDict["counts"] as? [String: Int]) ?? [:]
                    let pTechs = (pDict["technicians"] as? [String]) ?? []
                    let pAtendidoStr = String(describing: pDict["atendido_por_str"] ?? "Sin servicios previos")

                    var pTechsDetail: [TechnicianDetailItem] = []
                    if let rawTechDetail = pDict["technicians_detail"] as? [[String: Any]] {
                        for td in rawTechDetail {
                            let tName = String(describing: td["tecnico"] ?? "")
                            let tFecha = String(describing: td["fecha"] ?? "")
                            let tTiempo = String(describing: td["tiempo"] ?? "")
                            let tLabel = String(describing: td["tiempo_label"] ?? tTiempo)
                            let tTarifa = td["tarifa"] as? String
                            let tDisp = String(describing: td["display"] ?? "\(tName) • \(tFecha) • \(tLabel)")
                            if !tName.isEmpty {
                                pTechsDetail.append(TechnicianDetailItem(tecnico: tName, fecha: tFecha, tiempo: tTiempo, tiempoLabel: tLabel, tarifa: tTarifa, display: tDisp))
                            }
                        }
                    }

                    var pComments: [ClientComment] = []
                    if let rawComms = pDict["comments"] as? [[String: Any]] {
                        for comm in rawComms {
                            let cId = String(describing: comm["id"] ?? UUID().uuidString)
                            let cTxt = String(describing: comm["comentario"] ?? "")
                            let cDate = String(describing: comm["fecha_comentario"] ?? "")
                            pComments.append(ClientComment(id: cId, comentario: cTxt, fecha_comentario: cDate))
                        }
                    }

                    var pConv: [TodayMessage] = []
                    if let rawConv = pDict["conversation"] as? [[String: Any]] {
                        for m in rawConv {
                            let mId = String(describing: m["id"] ?? UUID().uuidString)
                            let mMsg = String(describing: m["message"] ?? "")
                            let mDate = String(describing: m["date"] ?? "")
                            let mTs = (m["timestamp"] as? Double) ?? (Double(m["timestamp"] as? Int ?? 0))
                            let mLk = String(describing: m["line_key"] ?? "RAFAELLA")
                            let mLn = String(describing: m["line_name"] ?? mLk)
                            let mIsToday = (m["is_today"] as? Bool) ?? true
                            pConv.append(TodayMessage(id: mId, message: mMsg, date: mDate, timestamp: mTs, lineKey: mLk, lineName: mLn, isToday: mIsToday))
                        }
                    }

                    let profileData = ClientProfileData(
                        found: pFound,
                        primaryName: pName,
                        serviceCount: pSvcCount,
                        totalRevenue: pTotRev,
                        revenue30Days: pRev30,
                        clientRank: pRank,
                        counts: pCounts,
                        technicians: pTechs,
                        techniciansDetail: pTechsDetail,
                        atendidoPorStr: pAtendidoStr,
                        comments: pComments,
                        conversation: pConv
                    )

                    DispatchQueue.main.async {
                        if let idx = self?.contacts.firstIndex(where: { $0.cleanPhone == clean }) {
                            self?.contacts[idx].profile = profileData
                        }
                        completion(profileData)
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }

    // Guardar nuevo comentario o nota para un cliente
    func addComment(phone: String, comment: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverUrl)?action=add_comment&token=\(apiToken)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["telefono": phone, "comentario": comment]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let success = (error == nil)
            DispatchQueue.main.async {
                if success {
                    self?.fetchClientProfile(phone: phone) { _ in
                        self?.fetchLatestData()
                    }
                }
                completion(success)
            }
        }.resume()
    }

    // Modificar un comentario / nota existente
    func updateComment(phone: String, commentId: String, newComment: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverUrl)?action=update_comment&token=\(apiToken)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["id": commentId, "telefono": phone, "comentario": newComment]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let success = (error == nil)
            DispatchQueue.main.async {
                if success {
                    self?.fetchClientProfile(phone: phone) { _ in
                        self?.fetchLatestData()
                    }
                }
                completion(success)
            }
        }.resume()
    }

    // Eliminar un comentario / nota existente
    func deleteComment(phone: String, commentId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverUrl)?action=delete_comment&token=\(apiToken)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["id": commentId, "telefono": phone]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let success = (error == nil)
            DispatchQueue.main.async {
                if success {
                    self?.fetchClientProfile(phone: phone) { _ in
                        self?.fetchLatestData()
                    }
                }
                completion(success)
            }
        }.resume()
    }

    // Actualizar nombre o alias del cliente/contacto
    func updateClientName(phone: String, newName: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverUrl)?action=update_client_name&token=\(apiToken)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["telefono": phone, "nombre": newName]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let success = (error == nil)
            DispatchQueue.main.async {
                if success {
                    self?.fetchLatestData()
                }
                completion(success)
            }
        }.resume()
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
