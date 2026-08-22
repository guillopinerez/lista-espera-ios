import SwiftUI
import UserNotifications
import AudioToolbox

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("🔔 Permiso de notificaciones: \(granted)")
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let title = notification.request.content.title
        if title.contains("CLIENTE") || title.contains("🌟") {
            AudioServicesPlaySystemSound(1025) // 🌟 Campana VIP doble alegre para Cliente Registrado
        } else {
            AudioServicesPlaySystemSound(1007) // 📱 Sonido de notificación estándar para Contacto Nuevo
        }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

@main
struct ListaEsperaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncEngine = BackgroundSyncEngine.shared

    var body: some Scene {
        WindowGroup {
            ClientCardsView()
                .preferredColorScheme(.light)
        }
    }
}
