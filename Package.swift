// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "ListaEspera",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "ListaEspera",
            targets: ["AppModule"],
            bundleIdentifier: "com.amoravias.listadeespera",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .list),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .portraitUpsideDown
            ],
            capabilities: [
                .outgoingNetworkConnections(),
                .backgroundExecution(modes: [.audio, .fetch, .processing]),
                .userNotifications()
            ],
            additionalInfoPlistContentFilePath: "CustomInfoPlist.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
