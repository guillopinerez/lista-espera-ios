import Foundation
import SwiftUI

// Modelo de Cliente / Contacto para la Tarjeta
struct ClientContact: Identifiable, Codable, Equatable {
    var id: String { phone }
    let phone: String
    var displayName: String?
    var atendidoPor: String?
    var lastMessage: String
    var lastLine: String
    var lastTimestamp: Double
    var detectedTime: String?
    var queueStatus: String // "waiting", "in_service", "served", "none"
    var waitingSince: Double?
    var unreadCount: Int

    var formattedPhone: String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+1") && cleaned.count == 12 {
            let area = cleaned.dropFirst(2).prefix(3)
            let mid = cleaned.dropFirst(5).prefix(3)
            let end = cleaned.dropFirst(8).prefix(4)
            return "+1 (\(area)) \(mid)-\(end)"
        }
        return phone
    }

    var timeAgo: String {
        let now = Date().timeIntervalSince1970
        let diff = max(0, Int(now - lastTimestamp))
        if diff < 60 { return "hace \(diff)s" }
        let mins = diff / 60
        if mins < 60 { return "hace \(mins) min" }
        let hours = mins / 60
        return "hace \(hours) h"
    }

    var lineColor: Color {
        let u = lastLine.uppercased()
        if u.contains("RAFAELLA") { return Color(red: 0.745, green: 0.071, blue: 0.235) } // #be123c
        if u.contains("EMILIA") { return Color(red: 0.114, green: 0.306, blue: 0.847) }   // #1d4ed8
        if u.contains("NATALIA") { return Color(red: 0.706, green: 0.325, blue: 0.035) }  // #b45309
        if u.contains("PEDRO") { return Color(red: 0.016, green: 0.471, blue: 0.341) }    // #047857
        if u.contains("CARLOS") { return Color(red: 0.427, green: 0.157, blue: 0.851) }   // #6d28d9
        return Color.blue
    }
}

// Evento SMS entrante
struct SmsEvent: Identifiable, Codable {
    let id: String
    let phone: String
    let message: String
    let line_key: String?
    let device: String?
    let date: String?
    let timestamp: Double?
}

// Configuración de Línea
struct LineConfig: Identifiable, Codable {
    let id: String
    let name: String
    let color: String
    let serial: String?
    let lastSeen: Double?
    let active: Bool?
}
