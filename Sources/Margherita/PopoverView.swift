import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var model: IndicatorModel

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            updateBanner
            statusBanners
            
            HStack(alignment: .top, spacing: 12) {
                IndicatorPreview(model: model)
                    .frame(width: 48, height: 48)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    // Decorativa: los readouts a la derecha ya exponen los números.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    if model.dataSource == .statusLine {
                        // Datos reales: solo lectura, sin sliders.
                        readoutRow(title: Localizer.shared.tr("availability"), value: model.percent, accent: .primary)
                        if model.percent == 0 {
                            // Cuenta atrás humana ("Se restablece en 3 hora(s)").
                            HStack {
                                Text(Localizer.shared.tr("reset_in"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Spacer()
                                Text(model.resetETAText ?? Localizer.shared.tr("soon"))
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Modo manual: sliders de prueba.
                        sliderRow(title: Localizer.shared.tr("availability"), value: $model.percent, accent: .primary)
                        if model.percent == 0 {
                            sliderRow(title: Localizer.shared.tr("reset_progress"), value: $model.resetProgress, accent: .secondary)
                        }
                    }
                }
            }

            sourceLine

            if model.dataSource == .statusLine && !model.meters.isEmpty {
                allMetersSection
            }

            integrationSection

            Divider()

            Picker(Localizer.shared.tr("shape"), selection: $model.shape) {
                Text(Localizer.shared.tr("circle")).tag(IndicatorShape.circle)
                Text(Localizer.shared.tr("polygon")).tag(IndicatorShape.polygon)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.shape == .polygon {
                HStack {
                    Text(Localizer.shared.tr("sides"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker(Localizer.shared.tr("sides"), selection: $model.polygonSides) {
                        ForEach(Array(IndicatorModel.polygonSidesRange), id: \.self) { k in
                            Text("\(k)").tag(k)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(Localizer.shared.tr("system_prefs"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Toggle(Localizer.shared.tr("launch_at_login"), isOn: $model.isLaunchAtLoginEnabled)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Toggle(Localizer.shared.tr("notifications_enable"), isOn: $model.isNotificationsEnabled)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Toggle(Localizer.shared.tr("show_percent"), isOn: $model.showPercentInMenuBar)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider()

            Toggle(Localizer.shared.tr("manual_slider"), isOn: Binding(
                get: { model.dataSource == .manual },
                set: { model.dataSource = $0 ? .manual : .statusLine }
            ))
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Spacer()
                Button(Localizer.shared.tr("quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            // Re-chequear al abrir: el aviso de jq/hook se limpia sin relanzar.
            model.checkJqInstallation()
            model.checkHookInstallation()
        }
    }

    // MARK: - Subvistas

    @ViewBuilder
    private var updateBanner: some View {
        if model.isUpdateAvailable {
            HStack(spacing: 6) {
                Button {
                    if let url = URL(string: model.latestVersionURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Localizer.shared.tr("update_available_title"))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(Localizer.shared.tr("update_available_body", model.latestVersionString))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.latestVersionNotes.isEmpty
                      ? Localizer.shared.tr("update_available_body", model.latestVersionString)
                      : model.latestVersionNotes)

                // Omitir esta versión: no se vuelve a anunciar.
                Button {
                    model.skipCurrentUpdate()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Localizer.shared.tr("skip_version"))
                .accessibilityLabel(Localizer.shared.tr("skip_version"))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                // Verde/teal oscuros para que el texto blanco supere WCAG AA (~4.5:1).
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.44, blue: 0.30),
                             Color(red: 0.09, green: 0.40, blue: 0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        if model.dataSource == .statusLine {
            if !model.isWatcherActive {
                // El observador de ~/.claude no arrancó: los datos no se refrescarán.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundColor(.red)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localizer.shared.tr("watcher_inactive"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text(Localizer.shared.tr("watcher_inactive_desc"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if model.updatedAt == nil {
                // Banner de espera inicial
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.blue)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localizer.shared.tr("waiting_data"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text(Localizer.shared.tr("waiting_data_desc"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if model.isDataStale {
                // Banner de datos desactualizados (Stale)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.clock.fill")
                        .foregroundColor(.orange)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localizer.shared.tr("stale_data"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text(Localizer.shared.tr("stale_data_desc"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            // Modo manual: aviso claro de que los datos NO son reales.
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.orange)
                    .font(.body)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localizer.shared.tr("manual_active"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Text(Localizer.shared.tr("manual_active_desc"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Linea que indica el origen de los datos.
    @ViewBuilder
    private var sourceLine: some View {
        HStack(spacing: 4) {
            Image(systemName: model.dataSource == .statusLine
                  ? "antenna.radiowaves.left.and.right"
                  : "slider.horizontal.3")
                .font(.caption2)
                .accessibilityHidden(true)
            Text(sourceText)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }

    private var sourceText: String {
        switch model.dataSource {
        case .statusLine:
            var text = Localizer.shared.tr("source_claude", meterLabel(model.primaryMeter))
            if let updated = model.updatedAt {
                let rel = Self.relativeFormatter.localizedString(
                    for: updated, relativeTo: Date()
                )
                text += " · \(rel)"
            }
            return text
        case .manual:
            return Localizer.shared.tr("source_manual")
        }
    }

    @ViewBuilder
    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Advertencia de jq si no está instalado
            if !model.isJqInstalled {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Localizer.shared.tr("jq_missing"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text(Localizer.shared.tr("jq_missing_desc"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install jq", forType: .string)
                        } label: {
                            Label(Localizer.shared.tr("copy_command"), systemImage: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.link)
                        .help("brew install jq")
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localizer.shared.tr("claude_integration"))
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.isHookInstalled ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(model.isHookInstalled ? Localizer.shared.tr("linked") : Localizer.shared.tr("not_linked"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if model.isHookInstalled {
                        model.uninstallHook()
                    } else {
                        model.installHook()
                    }
                }) {
                    Text(model.isHookInstalled ? Localizer.shared.tr("unlink") : Localizer.shared.tr("link"))
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }

            if let hookError = model.hookError {
                Text(hookError)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Lista de TODOS los meters del último payload (no solo el primario).
    /// Cada fila muestra disponibilidad + barra y permite elegir cuál alimenta
    /// el icono; el activo queda resaltado.
    @ViewBuilder
    private var allMetersSection: some View {
        let activeKey = model.effectiveMeterKey
        VStack(alignment: .leading, spacing: 6) {
            Text(Localizer.shared.tr("meters"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            ForEach(model.meters.keys.sorted(), id: \.self) { key in
                meterRow(key: key, isActive: key == activeKey)
            }
        }
    }

    @ViewBuilder
    private func meterRow(key: String, isActive: Bool) -> some View {
        let used = model.meters[key]?.usedPercentage ?? 0
        let avail = max(0.0, min(100.0, 100.0 - used))
        Button {
            model.primaryMeter = key
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 9))
                        .foregroundColor(isActive ? .accentColor : .secondary)
                        .accessibilityHidden(true)
                    Text(meterLabel(key))
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(format: "%.0f%%", avail))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                // Barra propia (Capsule) en vez de ProgressView: .tint sobre
                // ProgressView lineal no es fiable antes de macOS 15.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(avail / 100.0))
                    }
                }
                .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meterLabel(key))
        .accessibilityValue(String(format: "%.0f%%", avail))
        .accessibilityHint(Localizer.shared.tr("a11y_meter_hint"))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func meterLabel(_ key: String) -> String {
        return Localizer.shared.meterLabel(key)
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.1f%%", value.wrappedValue))
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundColor(accent)
            }
            Slider(value: value, in: 0...100)
        }
    }

    @ViewBuilder
    private func readoutRow(title: String, value: Double, accent: Color) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(String(format: "%.1f%%", value))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundColor(accent)
        }
    }
}

/// Preview vectorial dentro del popover. Espeja la geometria y la
/// semantica de template image de IconRenderer: lo "disponible" se
/// pinta con Color.primary (foreground adaptativo: negro en light mode,
/// blanco en dark mode) y la parte "consumida" no se pinta (deja ver el
/// fondo del control). Eso refleja el comportamiento real del icono en
/// la menu bar, donde macOS tinta segun el fondo.
struct IndicatorPreview: View {
    @ObservedObject var model: IndicatorModel

    private static let fgFull = Color.primary
    private static let fgFaded = Color.primary.opacity(IconRenderer.resetAlpha)

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2.0 - 2.0

            if model.dataSource == .statusLine && model.updatedAt == nil {
                drawPlaceholder(ctx: ctx, center: center, radius: radius,
                                shape: model.shape, polygonSides: model.polygonSides)
                return
            }

            switch model.shape {
            case .circle:
                drawCircle(ctx: ctx, center: center, radius: radius,
                           percent: model.percent, resetProgress: model.resetProgress)
            case .polygon:
                drawPolygon(ctx: ctx, center: center, radius: radius,
                            k: max(3, model.polygonSides),
                            percent: model.percent, resetProgress: model.resetProgress)
            }
        }
    }

    private func drawPlaceholder(
        ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
        shape: IndicatorShape, polygonSides: Int
    ) {
        var path = Path()
        switch shape {
        case .circle:
            path.addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
        case .polygon:
            let k = max(3, polygonSides)
            let base = -Double.pi / 2.0
            let stepRad = 2.0 * .pi / Double(k)
            let verts: [CGPoint] = (0..<k).map { i in
                let a = base - Double(i) * stepRad
                return CGPoint(x: center.x + radius * cos(a),
                               y: center.y + radius * sin(a))
            }
            if let first = verts.first {
                path.move(to: first)
                for i in 1..<k {
                    path.addLine(to: verts[i])
                }
                path.closeSubpath()
            }
        }

        ctx.stroke(
            path,
            with: .color(.primary.opacity(0.6)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .butt, lineJoin: .miter, dash: [2.0, 2.0])
        )
    }

    // Canvas Y-abajo: 12 en punto = -pi/2. CW visual = angulo ascendente.

    private func drawCircle(
        ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
        percent: Double, resetProgress: Double
    ) {
        let pct = min(100.0, max(0.0, percent))
        let reset = min(100.0, max(0.0, resetProgress))

        if pct > 0 {
            drawWedgeCW(ctx: ctx, center: center, radius: radius,
                        sweepRad: pct / 100.0 * (2 * .pi),
                        color: Self.fgFull)
        } else if reset > 0 {
            drawWedgeCW(ctx: ctx, center: center, radius: radius,
                        sweepRad: reset / 100.0 * (2 * .pi),
                        color: Self.fgFaded)
        }
    }

    /// Pie slice desde las 12 en CW visual (en Y-abajo: angulo creciente).
    private func drawWedgeCW(
        ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
        sweepRad: Double, color: Color
    ) {
        let bounds = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        if sweepRad >= 2 * .pi {
            ctx.fill(Path(ellipseIn: bounds), with: .color(color))
            return
        }
        let a0 = -Double.pi / 2.0
        let a1 = a0 + sweepRad
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center, radius: radius,
            startAngle: .radians(a0),
            endAngle: .radians(a1),
            clockwise: true
        )
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private func drawPolygon(
        ctx: GraphicsContext, center: CGPoint, radius: CGFloat, k: Int,
        percent: Double, resetProgress: Double
    ) {
        // Vertices CCW visualmente desde las 12 (Y-abajo => angulo decrece).
        let base = -Double.pi / 2.0
        let stepRad = 2.0 * .pi / Double(k)
        let verts: [CGPoint] = (0..<k).map { i in
            let a = base - Double(i) * stepRad
            return CGPoint(x: center.x + radius * cos(a),
                           y: center.y + radius * sin(a))
        }

        func segmentPath(_ i: Int) -> Path {
            var p = Path()
            p.move(to: center)
            p.addLine(to: verts[i])
            p.addLine(to: verts[(i + 1) % k])
            p.closeSubpath()
            return p
        }

        let pct = min(100.0, max(0.0, percent))
        let reset = min(100.0, max(0.0, resetProgress))

        if pct > 0 {
            let used = 100.0 - pct
            let usedN = Int((Double(k) * used / 100.0).rounded())
            for i in usedN..<k {
                ctx.fill(segmentPath(i), with: .color(Self.fgFull))
            }
        } else if reset > 0 {
            let grayN = Int((Double(k) * reset / 100.0).rounded())
            for i in (k - grayN)..<k {
                ctx.fill(segmentPath(i), with: .color(Self.fgFaded))
            }
        }
    }
}
