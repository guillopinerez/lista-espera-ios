import SwiftUI

struct ClientCardsView: View {
    @ObservedObject var engine = BackgroundSyncEngine.shared
    @State private var currentCardIndex: Int = 0
    @State private var selectedClientForDetail: ClientContact? = nil
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
        .sheet(item: $selectedClientForDetail) { client in
            ClientDetailSheetView(client: client, engine: engine)
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

                Text("Monitoreo y Notificaciones en Tiempo Real")
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
                            .background(engine.selectedLine == line ? Color(red: 0.12, green: 0.23, blue: 0.54) : Color.white)
                            .foregroundColor(engine.selectedLine == line ? .white : Color(red: 0.3, green: 0.35, blue: 0.45))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(engine.selectedLine == line ? Color.clear : Color(red: 0.88, green: 0.9, blue: 0.94), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.98, green: 0.99, blue: 1.0))
    }

    private var cardsCarouselView: some View {
        VStack(spacing: 6) {
            // Indicador de Posición
            HStack {
                Text("CLIENTE \(min(currentCardIndex + 1, filteredContacts.count)) DE \(filteredContacts.count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))

                Spacer()

                Text("👉 Desliza para navegar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Tarjeta Principal Interactiva con Paginación
            TabView(selection: $currentCardIndex) {
                ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, client in
                    cardItemView(client: client)
                        .tag(index)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 2)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        }
    }

    private func cardItemView(client: ClientContact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fila 1: Badge de Línea + Hora Relativa
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(client.lineColor)
                        .frame(width: 8, height: 8)

                    Text("📱 " + client.lastLine.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(client.lineColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(client.lineColor.opacity(0.12))
                .cornerRadius(6)

                Spacer()

                Text("⏱️ \(client.timeAgo)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))
            }

            // Fila 2: Nombre de Cliente / "NO ES CLIENTE" y Teléfono
            VStack(alignment: .leading, spacing: 2) {
                if client.isRegistered {
                    Text(client.notificationTitle)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(red: 0.12, green: 0.23, blue: 0.54))
                        .lineLimit(1)
                } else {
                    Text("⚠️ NO ES CLIENTE")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(Color(red: 0.85, green: 0.2, blue: 0.2))
                }

                Text(client.formattedPhone)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
            }

            // Fila 3: Conversación Unificada de Hoy (Todos los SMS recibidos)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("💬 CONVERSACIÓN DE HOY (\(client.todayMessages.count > 0 ? client.todayMessages.count : 1) SMS):")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))

                    Spacer()
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        if client.todayMessages.isEmpty {
                            HStack(alignment: .top, spacing: 5) {
                                Text("•")
                                    .foregroundColor(client.lineColor)
                                    .fontWeight(.black)
                                Text("\"\(client.lastMessage)\"")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                            }
                            .padding(4)
                        } else {
                            ForEach(client.todayMessages) { msg in
                                HStack(alignment: .top, spacing: 5) {
                                    Text(msg.timeFormatted)
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(client.lineColor)
                                        .padding(.top, 1)

                                    Text(msg.message)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                                }
                                .padding(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(5)
                            }
                        }
                    }
                }
                .frame(maxHeight: 80)
                .padding(6)
                .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                .cornerRadius(8)
            }

            // Fila 4: Tiempo Solicitado y Estado de Cola
            HStack(spacing: 6) {
                if let reqTime = client.detectedTime, !reqTime.isEmpty, reqTime != "No especificado" {
                    HStack(spacing: 3) {
                        Text("⏱️")
                        Text(reqTime)
                            .font(.system(size: 10.5, weight: .black))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.99, green: 0.95, blue: 0.88))
                    .foregroundColor(Color(red: 0.71, green: 0.33, blue: 0.04))
                    .cornerRadius(5)
                }

                Spacer()

                Text(client.queueStatus == "in_service" ? "🟢 EN ATENCIÓN" : "⏳ EN ESPERA")
                    .font(.system(size: 10.5, weight: .black))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(client.queueStatus == "in_service" ? Color(red: 0.92, green: 0.99, blue: 0.95) : Color(red: 0.95, green: 0.96, blue: 0.98))
                    .foregroundColor(client.queueStatus == "in_service" ? Color(red: 0.02, green: 0.47, blue: 0.34) : Color(red: 0.28, green: 0.33, blue: 0.41))
                    .cornerRadius(5)
            }

            // Fila 5: Botones de Acción (Elevados y Visibles)
            HStack(spacing: 8) {
                // Botón VER NOTAS destacado si el cliente tiene comentarios
                if client.hasNotes {
                    Button(action: {
                        selectedClientForDetail = client
                    }) {
                        HStack(spacing: 4) {
                            Text("📝 NOTAS (\(client.notesCount))")
                                .font(.system(size: 11, weight: .black))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color(red: 0.98, green: 0.85, blue: 0.25))
                        .foregroundColor(Color(red: 0.45, green: 0.18, blue: 0.0))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0.9, green: 0.7, blue: 0.0), lineWidth: 1.5)
                        )
                    }
                }

                // Botón Ver Detalle Completo
                Button(action: {
                    selectedClientForDetail = client
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.text.rectangle.fill")
                        Text("Ver Detalle")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.12, green: 0.23, blue: 0.54))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // Botón Llamar
                Button(action: {
                    let clean = client.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let url = URL(string: "tel://\(clean)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(9)
                        .background(Color(red: 0.92, green: 0.99, blue: 0.95))
                        .foregroundColor(Color(red: 0.02, green: 0.47, blue: 0.34))
                        .cornerRadius(8)
                }

                // Botón Copiar
                Button(action: {
                    UIPasteboard.general.string = "\(client.displayName ?? "Cliente"): \(client.phone) - \(client.lastMessage)"
                    showToast("📋 Copiado al portapapeles")
                }) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(9)
                        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
                        .foregroundColor(Color(red: 0.3, green: 0.35, blue: 0.45))
                        .cornerRadius(8)
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .onTapGesture {
            selectedClientForDetail = client
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray.fill")
                .font(.system(size: 44))
                .foregroundColor(Color(red: 0.75, green: 0.78, blue: 0.85))

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
        HStack(spacing: 10) {
            Button(action: {
                engine.triggerTestNotification()
                showToast("🔔 Notificación de prueba enviada")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                    Text("Probar Notificación")
                }
                .font(.system(size: 12.5, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color(red: 0.12, green: 0.23, blue: 0.54))
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            }

            Button(action: {
                if let topClient = filteredContacts.first {
                    selectedClientForDetail = topClient
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "person.crop.circle.fill")
                    Text("Detalle")
                }
                .font(.system(size: 12.5, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white)
                .foregroundColor(Color(red: 0.12, green: 0.23, blue: 0.54))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.88, green: 0.9, blue: 0.94), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
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

// --- VISTA DETALLADA DEL CLIENTE (IGUAL AL DASHBOARD WEB) ---
struct ClientDetailSheetView: View {
    let client: ClientContact
    @ObservedObject var engine: BackgroundSyncEngine
    @Environment(\.presentationMode) var presentationMode
    @State private var newCommentText: String = ""
    @State private var isSavingComment: Bool = false
    @State private var showingEditName: Bool = false
    @State private var newClientName: String = ""
    @State private var isSavingName: Bool = false
    @State private var detailedProfile: ClientProfileData? = nil
    @State private var commentToEdit: ClientComment? = nil
    @State private var showingEditAlert: Bool = false
    @State private var editText: String = ""
    @State private var commentToDelete: ClientComment? = nil
    @State private var showingDeleteAlert: Bool = false

    var activeProfile: ClientProfileData? { detailedProfile ?? client.profile }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Cabecera Principal del Cliente
                    clientHeaderSection

                    // 2. Toda la conversación de hoy
                    conversationSection

                    // 3. Métricas Contextuales (4 Cajas idénticas al Dashboard)
                    metricsSection

                    // 4. Técnicos que han atendido previamente
                    techniciansSection

                    // 5. Notas y Comentarios
                    commentsSection
                }
                .padding(16)
            }
            .onAppear {
                engine.fetchClientProfile(phone: client.cleanPhone) { fetched in
                    if let fetched = fetched {
                        self.detailedProfile = fetched
                    }
                }
            }
            .alert("Editar Nota", isPresented: $showingEditAlert) {
                TextField("Texto de la nota", text: $editText)
                Button("Guardar") {
                    if let c = commentToEdit {
                        let trimmed = editText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        engine.updateComment(phone: client.cleanPhone, commentId: c.id, newComment: trimmed) { success in
                            if success {
                                engine.fetchClientProfile(phone: client.cleanPhone) { fetched in
                                    if let fetched = fetched {
                                        self.detailedProfile = fetched
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Modifica el contenido de esta nota:")
            }
            .alert("Eliminar Nota", isPresented: $showingDeleteAlert) {
                Button("Eliminar", role: .destructive) {
                    if let c = commentToDelete {
                        engine.deleteComment(phone: client.cleanPhone, commentId: c.id) { success in
                            if success {
                                engine.fetchClientProfile(phone: client.cleanPhone) { fetched in
                                    if let fetched = fetched {
                                        self.detailedProfile = fetched
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("¿Desea eliminar permanentemente esta nota?")
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.98).ignoresSafeArea())
            .navigationBarTitle("Detalle de Cliente", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cerrar") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }

    private var clientHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                if client.isRegistered {
                    Text(client.notificationTitle)
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(Color(red: 0.12, green: 0.23, blue: 0.54))
                } else {
                    Text("⚠️ NO ES CLIENTE REGISTRADO")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(red: 0.85, green: 0.2, blue: 0.2))
                }

                Button(action: {
                    newClientName = client.displayName ?? ""
                    withAnimation {
                        showingEditName.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                        Text("Editar")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.9, green: 0.95, blue: 1.0))
                    .foregroundColor(Color(red: 0.12, green: 0.45, blue: 0.75))
                    .cornerRadius(6)
                }

                Spacer()

                Text("📱 \(client.lastLine.uppercased())")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(client.lineColor.opacity(0.12))
                    .foregroundColor(client.lineColor)
                    .cornerRadius(6)
            }

            // Formulario desplegable para cambiar nombre
            if showingEditName {
                HStack(spacing: 8) {
                    TextField("Nuevo nombre del cliente...", text: $newClientName)
                        .font(.system(size: 13, weight: .medium))
                        .padding(8)
                        .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0.85, green: 0.9, blue: 0.95), lineWidth: 1)
                        )

                    Button(action: {
                        let trimmed = newClientName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        isSavingName = true
                        engine.updateClientName(phone: client.cleanPhone, newName: trimmed) { success in
                            isSavingName = false
                            if success {
                                withAnimation {
                                    showingEditName = false
                                }
                            }
                        }
                    }) {
                        Text(isSavingName ? "..." : "Guardar")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.12, green: 0.23, blue: 0.54))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button("Cancelar") {
                        withAnimation {
                            showingEditName = false
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(red: 0.98, green: 0.99, blue: 1.0))
                .cornerRadius(10)
            }

            Text(client.formattedPhone)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))

            HStack(spacing: 10) {
                Button(action: {
                    let clean = client.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let url = URL(string: "tel://\(clean)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "phone.fill")
                        Text("Llamar")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.92, green: 0.99, blue: 0.95))
                    .foregroundColor(Color(red: 0.02, green: 0.47, blue: 0.34))
                    .cornerRadius(8)
                }

                Button(action: {
                    UIPasteboard.general.string = client.phone
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                        Text("Copiar Número")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(Color(red: 0.2, green: 0.25, blue: 0.35))
                    .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(14)
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💬 TODA LA CONVERSACIÓN DE HOY (\(client.todayMessages.count > 0 ? client.todayMessages.count : 1) SMS)")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(Color(red: 0.06, green: 0.45, blue: 0.75))

            VStack(spacing: 8) {
                if client.todayMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("📱 \(client.lastLine.uppercased())")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(client.lineColor)
                            Spacer()
                            Text(client.timeAgo)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                        }
                        Text(client.lastMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(10)
                } else {
                    ForEach(client.todayMessages) { msg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("📱 \(msg.lineName.uppercased())")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(client.lineColor)
                                Spacer()
                                Text(msg.timeFormatted + " (NYC)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                            }
                            Text(msg.message)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.25))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📊 MÉTRICAS DEL CLIENTE")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(Color(red: 0.3, green: 0.35, blue: 0.45))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricBox(title: "TOTAL HISTÓRICO", value: "$\(Int(activeProfile?.totalRevenue ?? 0))", color: Color(red: 0.85, green: 0.65, blue: 0.13))
                metricBox(title: "ÚLTIMOS 30 DÍAS", value: "$\(Int(activeProfile?.revenue30Days ?? 0))", color: Color(red: 0.05, green: 0.65, blue: 0.45))
                metricBox(title: "RANKING", value: activeProfile?.found == true ? "#\(activeProfile?.clientRank ?? 1)" : "N/A", color: Color(red: 0.05, green: 0.55, blue: 0.85))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL SERVICIOS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                    Text("\(activeProfile?.serviceCount ?? 0)")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(Color(red: 0.55, green: 0.25, blue: 0.85))
                    
                    let c = activeProfile?.counts ?? [:]
                    Text("SS (15m): \(c["SS"] ?? 0) | HH (30m): \(c["HH"] ?? 0)\nH (1h): \(c["H"] ?? 0) | 2H (2h): \(c["2H"] ?? 0)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(10)
            }
        }
    }

    private func metricBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
            Text(value)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(10)
    }

    private var techniciansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("👩‍💼 ATENDIDO PREVIAMENTE POR:")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(Color(red: 0.06, green: 0.45, blue: 0.75))

            let techsDetail = activeProfile?.techniciansDetail ?? []
            if techsDetail.isEmpty {
                Text("Sin servicios previos registrados")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(10)
            } else {
                VStack(spacing: 6) {
                    ForEach(techsDetail) { item in
                        HStack {
                            HStack(spacing: 5) {
                                Text("👤")
                                Text(item.tecnico)
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(Color(red: 0.08, green: 0.15, blue: 0.28))
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                Text("📅 " + item.fecha)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 0.55))

                                Text("⏱️ " + item.tiempoLabel)
                                    .font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.99, green: 0.95, blue: 0.88))
                                    .foregroundColor(Color(red: 0.71, green: 0.33, blue: 0.04))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.9, green: 0.96, blue: 1.0))
                        .cornerRadius(8)
                    }
                }
                .padding(8)
                .background(Color.white)
                .cornerRadius(10)
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📝 NOTAS Y COMENTARIOS")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(Color(red: 0.3, green: 0.35, blue: 0.45))

            // Campo para agregar nota
            HStack(spacing: 8) {
                TextField("Escribir nota para este cliente...", text: $newCommentText)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(8)

                Button(action: {
                    let commentToSave = newCommentText.trimmingCharacters(in: .whitespaces)
                    guard !commentToSave.isEmpty else { return }
                    isSavingComment = true
                    engine.addComment(phone: client.cleanPhone, comment: commentToSave) { success in
                        isSavingComment = false
                        if success {
                            newCommentText = ""
                            engine.fetchClientProfile(phone: client.cleanPhone) { fetched in
                                if let fetched = fetched {
                                    self.detailedProfile = fetched
                                }
                            }
                        }
                    }
                }) {
                    Text(isSavingComment ? "..." : "Guardar")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.12, green: 0.23, blue: 0.54))
                        // Lista de comentarios anteriores (Diseño Vertical Amplio y Legible)
            let comments = activeProfile?.comments ?? []
            if comments.isEmpty {
                Text("Sin notas ni comentarios registrados.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.55, blue: 0.65))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(10)
            } else {
                VStack(spacing: 10) {
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: 10) {
                            // 1. Texto completo de la nota bien amplio, claro y legible
                            Text(c.comentario)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.08, green: 0.12, blue: 0.22))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()

                            // 2. Fila inferior: Timestamp a la izquierda + Botones Editar/Borrar a la derecha
                            HStack(alignment: .center) {
                                Text("🕒 \(c.fecha_comentario)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))

                                Spacer()

                                HStack(spacing: 8) {
                                    Button(action: {
                                        commentToEdit = c
                                        editText = c.comentario
                                        showingEditAlert = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                            Text("Editar")
                                        }
                                        .font(.system(size: 11.5, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(red: 0.88, green: 0.95, blue: 1.0))
                                        .foregroundColor(Color(red: 0.01, green: 0.41, blue: 0.63))
                                        .cornerRadius(6)
                                    }

                                    Button(action: {
                                        commentToDelete = c
                                        showingDeleteAlert = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                            Text("Borrar")
                                        }
                                        .font(.system(size: 11.5, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(red: 0.99, green: 0.88, blue: 0.88))
                                        .foregroundColor(Color(red: 0.6, green: 0.1, blue: 0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.85, green: 0.9, blue: 0.95), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                    }
                }
            }
        }
    }
}
}
}
