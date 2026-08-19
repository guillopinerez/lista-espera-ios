import Foundation
import SwiftUI

// Mensaje individual dentro de la conversación del día
struct TodayMessage: Identifiable, Codable, Equatable {
    var id: String
    var message: String
    var date: String
    var timestamp: Double
    var lineKey: String
    var lineName: String
    var isToday: Bool

    var timeFormatted: String {
        if timestamp > 0 {
            let d = Date(timeIntervalSince1970: timestamp)
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            f.timeZone = TimeZone(identifier: "America/New_York")
            return f.string(from: d)
        }
        if date.contains(" ") {
            return String(date.split(separator: " ").last ?? "")
        }
        return date
    }
}

// Comentario u Observación
struct ClientComment: Identifiable, Codable, Equatable {
    var id: String
    var comentario: String
    var fecha_comentario: String
}

// Perfil Histórico Completo del Cliente
struct ClientProfileData: Codable, Equatable {
    var found: Bool
    var primaryName: String
    var serviceCount: Int
    var totalRevenue: Double
    var revenue30Days: Double
    var clientRank: Int
    var counts: [String: Int]
    var technicians: [String]
    var atendidoPorStr: String
    var comments: [ClientComment]
    var conversation: [TodayMessage]
}

// Modelo de Cliente / Contacto para la Tarjeta
struct ClientContact: Identifiable, Codable, Equatable {
    var id: String { phone + "_" + lastLine }
    let cleanPhone: String
    let phone: String
    var displayName: String?
    var atendidoPor: String?
    var technicians: [String]
    var lastMessage: String
    var lastLine: String
    var lastTimestamp: Double
    var detectedTime: String?
    var queueStatus: String // "waiting", "in_service", "served", "none"
    var waitingSince: Double?
    var unreadCount: Int
    var todayMessages: [TodayMessage]
    var profile: ClientProfileData?

    var isRegistered: Bool {
        if let name = displayName, !name.isEmpty, name != "No es cliente registrado", name != "NO ES CLIENTE" {
            return true
        }
        return false
    }

    var notificationTitle: String {
        if isRegistered, let name = displayName {
            return "👤 \(name.uppercased())"
        }
        return "⚠️ NO ES CLIENTE"
    }

    var formattedPhone: String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+1") && cleaned.count == 12 {
            let area = cleaned.dropFirst(2).prefix(3)
            let mid = cleaned.dropFirst(5).prefix(3)
            let end = cleaned.dropFirst(8).prefix(4)
            return "+1 (\(area)) \(mid)-\(end)"
        }
        if cleaned.count == 10 {
            let area = cleaned.prefix(3)
            let mid = cleaned.dropFirst(3).prefix(3)
            let end = cleaned.dropFirst(6).prefix(4)
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
