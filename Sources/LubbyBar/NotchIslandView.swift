import AppKit
import SwiftUI

/// Shared open/closed state for the island. Hover expands transiently; a click
/// pins it open (the controller watches `pinned` to dismiss on an outside click).
final class NotchState: ObservableObject {
    @Published var pinned = false
}

/// Reported up to the window controller so the window hugs the pill/drawer
/// exactly. `leftEar` is the width left of the notch gap, so the controller can
/// align the gap with the physical notch even when the two ears differ in width.
struct IslandLayout: Equatable {
    var size: CGSize
    var leftEar: CGFloat
}

struct IslandLayoutKey: PreferenceKey {
    static var defaultValue = IslandLayout(size: .zero, leftEar: 0)
    static func reduce(value: inout IslandLayout, nextValue: () -> IslandLayout) {
        let next = nextValue()
        if next.size != .zero { value = next }
    }
}

/// The rounded blob that hugs the notch: square top corners (flush with the
/// screen bezel) with a small concave fillet, and rounded bottom corners, so the
/// pill reads as an extension of the physical notch and the expanded panel reads
/// as a drawer hanging off it.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = 12
    var topFillet: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        let f = min(topFillet, r)

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + f, y: rect.minY + f),
            control: CGPoint(x: rect.minX + f, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + f + r, y: rect.maxY),
            control: CGPoint(x: rect.minX + f, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - f, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX - f, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - f, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// A status dot with a soft glow and, while running, an expanding "radar" ring
/// that pulses outward. Gives the live, working feel.
struct StatusDot: View {
    let status: Status
    var size: CGFloat = 11

    @State private var pulse = false

    var body: some View {
        ZStack {
            if status == .running {
                Circle()
                    .stroke(status.color, lineWidth: 1.5)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.6)
            }
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)
                .shadow(color: status.color.opacity(0.8), radius: size * 0.45)
        }
        .frame(width: size, height: size)
        .onAppear(perform: restartPulse)
        .onChange(of: status) { _ in restartPulse() }
    }

    private func restartPulse() {
        pulse = false
        guard status == .running else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

/// A single round status light split into proportional pie slices: one slice per
/// status, sized to how many sessions hold it (e.g. 1 running + 2 waiting ->
/// ~33% green, ~67% orange). A solid color when all sessions share a status.
struct ProportionalDot: View {
    let statuses: [Status]
    var size: CGFloat = 13

    private var stops: [Gradient.Stop] {
        let order: [Status] = [.running, .waitingInput, .stopped, .idle]
        let total = max(1, statuses.count)
        var out: [Gradient.Stop] = []
        var cursor = 0.0
        for status in order {
            let count = statuses.filter { $0 == status }.count
            guard count > 0 else { continue }
            out.append(.init(color: status.color, location: cursor))
            cursor += Double(count) / Double(total)
            out.append(.init(color: status.color, location: min(cursor, 1)))
        }
        if out.isEmpty {
            out = [.init(color: Status.idle.color, location: 0),
                   .init(color: Status.idle.color, location: 1)]
        }
        return out
    }

    private var dominant: Color {
        let order: [Status] = [.running, .waitingInput, .stopped, .idle]
        var best = Status.idle
        var bestCount = -1
        for status in order {
            let count = statuses.filter { $0 == status }.count
            if count > bestCount { bestCount = count; best = status }
        }
        return best.color
    }

    var body: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: stops), center: .center))
            .rotationEffect(.degrees(-90)) // start the first slice at 12 o'clock
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
            .shadow(color: dominant.opacity(0.7), radius: size * 0.42)
    }
}

/// A small header action button (gear, power) with hover feedback so the top bar
/// feels responsive. Owns its tap so it never collapses the panel.
struct IconButton: View {
    let systemName: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
            .frame(width: 26, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.16 : 0.08))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The hero status icon: a rounded-square tile tinted with the status color and
/// a glyph, echoing NotchBox's album art. An expanding ring pulses while running.
struct StatusBadge: View {
    let status: Status

    @State private var pulse = false

    private var glyph: String {
        switch status {
        case .running: return "bolt.fill"
        case .waitingInput: return "bell.fill"
        case .stopped: return "stop.fill"
        case .idle: return "moon.fill"
        }
    }

    var body: some View {
        ZStack {
            if status == .running {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(status.color, lineWidth: 1.5)
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulse ? 1.32 : 1)
                    .opacity(pulse ? 0 : 0.5)
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(status.color.opacity(0.16))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(status.color.opacity(0.45), lineWidth: 1)
                )
            Image(systemName: glyph)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .shadow(color: status.color.opacity(0.45), radius: 10)
        .onAppear(perform: restart)
        .onChange(of: status) { _ in restart() }
    }

    private func restart() {
        pulse = false
        guard status == .running else { return }
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

/// The content drawn inside the notch-island window. Collapsed it is a thin pill
/// hugging the notch (dot + active project). On hover or when pinned it grows
/// into a drawer: a header with the rolled-up status and live uptime, then one
/// monospaced row per Claude session with its own dot, agent, and elapsed time.
struct NotchIslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchState
    var menuBarHeight: CGFloat
    var notchWidth: CGFloat
    var onLayout: (IslandLayout) -> Void
    var onSettings: () -> Void

    // Click-only: hovering the bare dot would make the window jump from
    // beside-the-notch to centered, moving the tracking area out from under the
    // cursor and flickering. So the dot expands on click and dismisses on an
    // outside click - no hover-driven resize.
    private var expanded: Bool { state.pinned }

    // Which panel page is showing.
    enum Page { case sessions, lubby }
    @State private var page: Page = .sessions

    // The currently-popped toast (an arriving alert), shown briefly then cleared.
    @State private var toast: Alert?
    // Fades content in as the window grows. Opacity only (never size) keeps the
    // open smooth without re-triggering window resizes.
    @State private var contentAlpha: Double = 0

    /// Three presentations share one window: the bare dot, a transient toast, and
    /// the full panel. Panel (a click) wins over a toast.
    enum Presentation { case dot, toast, panel }
    private var presentation: Presentation {
        if expanded { return .panel }
        if toast != nil { return .toast }
        return .dot
    }

    private var collapsedWidth: CGFloat { 34 }
    private var expandedWidth: CGFloat { 400 }
    private var toastWidth: CGFloat {
        guard let toast else { return collapsedWidth }
        let chars = CGFloat(min(toast.message.count, 30))
        return min(440, max(notchWidth + 150, chars * 8 + 130))
    }

    private var containerWidth: CGFloat {
        switch presentation {
        case .dot: return collapsedWidth
        case .toast: return toastWidth
        case .panel: return expandedWidth
        }
    }

    // Width left of the notch gap. The dot is the whole pill (lands left of the
    // notch); toast and panel center on the notch.
    private var leftEar: CGFloat {
        presentation == .dot ? collapsedWidth : (containerWidth - notchWidth) / 2
    }

    var body: some View {
        island
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: IslandLayoutKey.self,
                        value: IslandLayout(size: proxy.size, leftEar: leftEar)
                    )
                }
            )
            .onPreferenceChange(IslandLayoutKey.self) { onLayout($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            switch presentation {
            case .dot:
                ProportionalDot(statuses: sessionStatuses, size: 13)
                    .frame(width: collapsedWidth, height: menuBarHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { state.pinned.toggle() }
            case .toast:
                Color.clear.frame(height: menuBarHeight)
                toastRow.opacity(contentAlpha)
            case .panel:
                Color.clear.frame(height: menuBarHeight)
                drawer.frame(width: containerWidth).opacity(contentAlpha)
            }
        }
        .frame(width: containerWidth, alignment: .top)
        .background(background)
        .overlay(rim)
        .clipShape(shape)
        .contentShape(shape)
        .onChange(of: presentation == .dot) { isDot in
            if isDot {
                contentAlpha = 0
            } else {
                contentAlpha = 0
                withAnimation(.easeOut(duration: 0.3).delay(0.06)) { contentAlpha = 1 }
            }
        }
        .onChange(of: model.latestToast) { alert in
            guard let alert, !expanded else { return }
            showToast(alert)
        }
    }

    private var sessionStatuses: [Status] {
        model.sessions.map(\.status)
    }

    // MARK: - Toast

    private var toastRow: some View {
        HStack(spacing: 11) {
            Text(toast?.emoji ?? "🔔")
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 1) {
                Text(toast?.message ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Lubby")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .contentShape(Rectangle())
        .onTapGesture { openToast() }
    }

    private func showToast(_ alert: Alert) {
        toast = alert
        let shownID = alert.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if toast?.id == shownID, !expanded { toast = nil }
        }
    }

    private func openToast() {
        if let urlString = toast?.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        toast = nil
    }

    // MARK: - Expanded drawer

    private var drawer: some View {
        // Only the elapsed-time labels need a per-second tick, so each owns a
        // small TimelineView (see `ticking`). The rest is built once per real
        // data change, which keeps the open smooth and the dot pulses steady.
        VStack(spacing: 14) {
            headerBar
            switch page {
            case .sessions:
                hero
                sessionList
            case .lubby:
                if model.loggedIn {
                    presenceSection
                } else {
                    connectCTA
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    /// When not connected to the website, the Lubby page is a single call to
    /// action that kicks off the browser device-login.
    private var connectCTA: some View {
        VStack(spacing: 10) {
            Text("👋").font(.system(size: 32))
            Text("Connect to Lubby")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text("See who's coding nearby and get a ping when someone says hi.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { model.connect() }) {
                Text(model.loginInProgress ? "Connecting…" : "Connect")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.lubbyGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.loginInProgress)
            if let code = model.loginUserCode {
                Text("Approve in your browser · \(code)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// The engaging layer: who's waiting nearby and recent social pings, with a
    /// jump to the live map. Lubby mode only.
    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("👀").font(.system(size: 13))
                Text(nearbyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: { model.openMap() }) {
                    Text("Open map")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.lubbyGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !model.alerts.isEmpty {
                HStack(spacing: 8) {
                    Text("PINGS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer(minLength: 8)
                    Button(action: {
                        model.open(path: "/notifications")
                        state.pinned = false
                    }) {
                        Text("All →")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.lubbyOrange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            ForEach(model.alerts.prefix(3)) { alert in
                HStack(spacing: 9) {
                    Text(alert.emoji).font(.system(size: 13))
                    Text(alert.message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(alert.unread ? 0.95 : 0.55))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let when = Self.relativeTime(alert.createdAt) {
                        Text(when)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if alert.unread {
                        Circle().fill(Color.lubbyOrange).frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    if let s = alert.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
                    state.pinned = false
                }
            }

            peopleGroup("CONNECTIONS", model.connections)
            peopleGroup("NEARBY", model.nearbyPeople)
        }
    }

    @ViewBuilder
    private func peopleGroup(_ title: String, _ people: [Person]) -> some View {
        if !people.isEmpty {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
            ForEach(people.prefix(6)) { person in
                personRow(person)
            }
        }
    }

    private func personRow(_ person: Person) -> some View {
        HStack(spacing: 10) {
            avatar(person)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                if let place = person.placeLabel {
                    Text(place)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let tz = person.timezone, let zone = TimeZone(identifier: tz) {
                    TimelineView(.everyMinute) { context in
                        HStack(spacing: 5) {
                            Text(Self.clock(context.date, in: zone))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(Self.offsetLabel(zone))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                HStack(spacing: 4) {
                    StatusDot(status: person.status, size: 6)
                    Text(person.status.label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(person.status.color.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let u = person.username { model.open(path: "/u/\(u)") }
            state.pinned = false
        }
    }

    private func avatar(_ person: Person) -> some View {
        AsyncImage(url: person.avatarURL.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.lubbyGradient
                    Text(person.initials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Time helpers

    /// Compact "now / 4m / 2h / 3d" for a ping's age. Nil when undated.
    private static func relativeTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private static func clock(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func offsetLabel(_ zone: TimeZone) -> String {
        let mine = TimeZone.current.secondsFromGMT()
        let theirs = zone.secondsFromGMT()
        let diff = Double(theirs - mine) / 3600.0
        if abs(diff) < 0.01 { return "same time" }
        let sign = diff > 0 ? "+" : "−"
        let hours = abs(diff)
        let text = hours.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", hours)
            : String(format: "%.1f", hours)
        return "\(sign)\(text) hrs"
    }

    private var nearbyText: String {
        guard let nearby = model.nearby, nearby.total > 0 else {
            return "No one waiting nearby"
        }
        let people = nearby.total == 1 ? "1 waiting nearby" : "\(nearby.total) waiting nearby"
        if let stack = nearby.topStack, nearby.topStackCount > 0 {
            return "\(people) · \(nearby.topStackCount) on \(stack)"
        }
        return people
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.lubbyGradient)
                .frame(width: 8, height: 8)
                .padding(.trailing, 2)
            tab("Sessions", .sessions)
            tab("Lubby", .lubby)
            Spacer(minLength: 8)
            iconButton("gearshape") { onSettings() }
            iconButton("power") { NSApplication.shared.terminate(nil) }
        }
    }

    private func tab(_ title: String, _ value: Page) -> some View {
        let active = page == value
        return Text(title)
            .font(.system(size: 12, weight: active ? .bold : .medium))
            .foregroundStyle(active ? .white : .white.opacity(0.4))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(active ? Color.white.opacity(0.10) : Color.clear, in: Capsule())
            .overlay(
                // Unread badge on the Lubby tab when there are fresh pings.
                value == .lubby && model.alerts.contains(where: \.unread) && !active
                    ? AnyView(Circle().fill(Color.lubbyOrange).frame(width: 6, height: 6).offset(x: 4, y: -8))
                    : AnyView(EmptyView()),
                alignment: .topTrailing
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { page = value } }
    }

    /// Centered headline: the rolled-up status with a live uptime, NotchBox-style.
    private var hero: some View {
        VStack(spacing: 9) {
            statusBadge
            Text(model.status.label)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                if let recent = model.sessions.first?.updatedAt {
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    ticking(since: recent) { text in
                        Text(text)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(model.status.color)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        // Tapping the headline keeps the panel open (hover already expands it, so
        // this is the reliable "pin" affordance). Buttons/cards own their taps.
        .contentShape(Rectangle())
        .onTapGesture { state.pinned.toggle() }
    }

    private var statusBadge: some View {
        StatusBadge(status: model.status)
    }

    @ViewBuilder
    private var sessionList: some View {
        if model.sessions.isEmpty {
            Text("No active Claude sessions")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        } else {
            VStack(spacing: 7) {
                ForEach(model.sessions.prefix(5)) { session in
                    sessionRow(session)
                }
                if model.sessions.count > 5 {
                    Text("+\(model.sessions.count - 5) more")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 1)
                }
            }
        }
    }

    private func sessionRow(_ session: SessionInfo) -> some View {
        HStack(spacing: 10) {
            StatusDot(status: session.status, size: 8)
            Text(session.project ?? "—")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            statusChip(session.status)
            if let updated = session.updatedAt {
                ticking(since: updated) { text in
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        // The whole row is the hit target; clicking focuses that session's
        // terminal tab. contentShape makes the transparent gaps clickable too.
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalFocus.reveal(session)
            state.pinned = false
        }
        .help(session.tty == nil ? "Open project folder" : "Jump to this terminal")
    }

    /// Wraps a per-second elapsed-time label so only this small text re-renders on
    /// the tick, leaving the rest of the drawer (and the dot animations) untouched.
    private func ticking<V: View>(
        since date: Date, @ViewBuilder _ content: @escaping (String) -> V
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(elapsed(since: date, now: context.date))
        }
    }

    private func statusChip(_ status: Status) -> some View {
        Text(shortLabel(status))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(status.color.opacity(0.4), lineWidth: 0.5))
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        IconButton(systemName: systemName, action: action)
    }

    // MARK: - Styling

    private var shape: NotchShape {
        NotchShape(cornerRadius: presentation == .panel ? 26 : (presentation == .toast ? 20 : 12))
    }

    /// Toast and panel get the solid black NotchBox surface; the bare dot gets
    /// nothing, so the status light floats free in the menu bar.
    @ViewBuilder
    private var background: some View {
        if presentation != .dot {
            ZStack {
                Color.black
                RadialGradient(
                    colors: [model.status.color.opacity(0.14), Color.clear],
                    center: .top, startRadius: 0, endRadius: 170
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    startPoint: .top, endPoint: .center
                )
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var rim: some View {
        if presentation != .dot {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.8
            )
        }
    }

    // MARK: - Helpers

    private var subtitle: String {
        let count = model.sessions.count
        let source = model.sourceMode == .local ? "local" : "lubby"
        let label = count == 1 ? "session" : "sessions"
        return "\(source) · \(count) \(label)"
    }

    private func shortLabel(_ status: Status) -> String {
        switch status {
        case .running: return "RUN"
        case .waitingInput: return "WAIT"
        case .stopped: return "STOP"
        case .idle: return "IDLE"
        }
    }

    private func elapsed(since date: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(date)))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m\(s)s" }
        return "\(s)s"
    }
}

/// Lubby's Campfire brand palette, reused for the island chrome.
extension Color {
    static let lubbyOrange = Color(red: 1.0, green: 0.420, blue: 0.208) // #FF6B35
    static let lubbyGold = Color(red: 1.0, green: 0.718, blue: 0.012)   // #FFB703

    static let lubbyGradient = LinearGradient(
        colors: [lubbyOrange, lubbyGold],
        startPoint: .leading,
        endPoint: .trailing
    )
}
