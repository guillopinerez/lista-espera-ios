import SwiftUI

struct ClientCardsView: View {
    @ObservedObject var engine = BackgroundSyncEngine.shared
    @State private var currentCardIndex: Int = 0
    @State private var showingQuickQueueAlert: Bool = false
    @State private var toastMessage: String?

    var filteredContacts: [ClientContact] {
        if engine.selectedLine == "TODAS" {
            return engine.contacts
        }
        return engine.contacts.filter { $0.lastLine.uppercased().contains(engine.selectedLine.uppercased()) }
    }

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.96, blue: 0.98).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Cabecera de la App
                headerView

                // 2. Selector de Líneas
                lineSelectorBar

                // 3. Contenedor de Tarjetas de Clientes
                if filteredContacts.isEmpty {
                    emptyStateView
                } else {
                    cardsCarouselView
                }

                // 4. Barra de Acciones Inferior
                bottomActionBar
            }

            // Toast de notificación en pantalla
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(20)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: toastMessage)
            }
        }
    }

    // --- SUBVIEWS ---

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("⚡ Lista de Espera")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))

                    Text(engine.serverStatus)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.92, green: 0.99, blue: 0.95))
                        .foregroundColor(Color(red: 0.02, green: 0.47, blue: 0.34))
                        .cornerRadius(6)
                }

                Text("Tarjetas de Clientes en Tiempo Real")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))
            }

            Spacer()

            Button(action: {
                engine.fetchLatestData()
                showToast("🔄 Sincronizado con el servidor")
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.23, blue: 0.54))
                    .padding(8)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var lineSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(engine.activeLines, id: \.self) { line in
                    let isSelected = engine.selectedLine == line
                    Button(action: {
                        withAnimation {
                            engine.selectedLine = line
                            currentCardIndex = 0
                        }
                    }) {
                        Text(line)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color(red: 0.12, green: 0.23, blue: 0.54) : Color.white)
                            .foregroundColor(isSelected ? .white : Color(red: 0.28, green: 0.33, blue: 0.41))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
    }

    private var cardsCarouselView: some View {
        VStack(spacing: 12) {
            // Contador de posición de tarjeta
            HStack {
                Text("Cliente \(currentCardIndex + 1) de \(filteredContacts.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        if currentCardIndex > 0 {
                            withAnimation { currentCardIndex -= 1 }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentCardIndex > 0 ? Color(red: 0.12, green: 0.23, blue: 0.54) : Color.gray.opacity(0.3))
                    }
                    .disabled(currentCardIndex == 0)

                    Button(action: {
                        if currentCardIndex < filteredContacts.count - 1 {
                            withAnimation { currentCardIndex += 1 }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentCardIndex < filteredContacts.count - 1 ? Color(red: 0.12, green: 0.23, blue: 0.54) : Color.gray.opacity(0.3))
                    }
                    .disabled(currentCardIndex >= filteredContacts.count - 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Paginador de Tarjetas
            TabView(selection: $currentCardIndex) {
                ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, client in
                    clientCard(for: client)
                        .tag(index)
                        .padding(.horizontal, 16)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        }
    }

    private func clientCard(for client: ClientContact) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Encabezado de la Tarjeta
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(client.lineColor)
                        .frame(width: 10, height: 10)

                    Text(client.lastLine.uppercased())
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(client.lineColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(client.lineColor.opacity(0.12))
                .cornerRadius(8)

                Spacer()

                Text("⏱️ \(client.timeAgo)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))
            }

            // Teléfono Principal del Cliente
            VStack(alignment: .leading, spacing: 2) {
                Text("NÚMERO DE CONTACTO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))

                Text(client.formattedPhone)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
            }

            // Mensaje SMS Recibido
            VStack(alignment: .leading, spacing: 4) {
                Text("ÚLTIMO MENSAJE SMS:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))

                Text("\"\(client.lastMessage)\"")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .cornerRadius(10)
            }

            // Estado de la Cola
            HStack {
                Text("ESTADO DE COLA:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))

                Spacer()

                Text(client.queueStatus == "in_service" ? "🟢 EN ATENCIÓN" : "⏳ EN ESPERA")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(client.queueStatus == "in_service" ? Color(red: 0.92, green: 0.99, blue: 0.95) : Color(red: 0.95, green: 0.96, blue: 0.98))
                    .foregroundColor(client.queueStatus == "in_service" ? Color(red: 0.02, green: 0.47, blue: 0.34) : Color(red: 0.28, green: 0.33, blue: 0.41))
                    .cornerRadius(6)
            }

            Spacer()

            // Botones de Acción de la Tarjeta
            HStack(spacing: 10) {
                // Botón Llamar
                Button(action: {
                    if let url = URL(string: "tel://\(client.phone)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                        Text("Llamar")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(red: 0.02, green: 0.47, blue: 0.34))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Botón Copiar Número
                Button(action: {
                    UIPasteboard.general.string = client.phone
                    showToast("📋 Número copiado: \(client.phone)")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("Copiar")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(red: 0.12, green: 0.23, blue: 0.54))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 380)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 50))
                .foregroundColor(Color.gray.opacity(0.4))

            Text("Esperando clientes...")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 0.25, blue: 0.35))

            Text("Cualquier mensaje entrante creará automáticamente una tarjeta interactiva con notificaciones.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if let topClient = filteredContacts.first {
                    UIPasteboard.general.string = "\(topClient.phone): \(topClient.lastMessage)"
                    showToast("📋 Datos copiados al portapapeles")
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Compartir Contacto")
                }
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundColor(Color(red: 0.12, green: 0.23, blue: 0.54))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastMessage == msg {
                toastMessage = nil
            }
        }
    }
}
