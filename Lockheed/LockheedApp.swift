// LockheedApp.swift
// SwiftUI + SwiftData (iOS 17+)
// A minimal, elegant focus/reminder app with sections, tasks, due dates, local notifications, and confetti on completion.

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
public typealias UXView = UIView
public typealias UXViewRepresentable = UIViewRepresentable
public typealias UXColor = UIColor
#elseif os(macOS)
import AppKit
public typealias UXView = NSView
public typealias UXViewRepresentable = NSViewRepresentable
public typealias UXColor = NSColor
#endif

// MARK: - WindowMaximizer (macOS)

#if os(macOS)
struct WindowMaximizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, let screen = window.screen {
                let vf = screen.visibleFrame
                var frame = window.frame
                // Keep current width if it fits, otherwise clamp to visible width
                let targetWidth = min(frame.width, vf.width)
                frame.size = CGSize(width: targetWidth, height: vf.height)
                frame.origin.y = vf.origin.y // pin to bottom of visible frame
                frame.origin.x = max(vf.origin.x, frame.origin.x) // keep x if possible
                window.setFrame(frame, display: true, animate: true)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCatcherView()
        view.onScroll = onScroll
        // Make it clear background and accept first responder for events
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ScrollCatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func scrollWheel(with event: NSEvent) {
            super.scrollWheel(with: event)
            // Use scrollingDeltaY to respect natural scrolling
            onScroll?(event.scrollingDeltaY)
        }
    }
}
#endif

@main
struct LockheedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            #if os(macOS)
            .background(WindowMaximizer())
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 900)
        .windowStyle(.hiddenTitleBar)
        #endif
        .modelContainer(for: [FocusSection.self, FocusItem.self])
    }
}

// MARK: - Models.swift

import Foundation
import SwiftData

@Model
final class FocusSection: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var accentHex: String
    @Relationship(deleteRule: .cascade) var items: [FocusItem]

    init(id: UUID = UUID(), title: String, accentHex: String = "#7D7AFF", items: [FocusItem] = []) {
        self.id = id
        self.title = title
        self.accentHex = accentHex
        self.items = items
    }
}

@Model
final class FocusItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueDate: Date
    var startDate: Date?
    var isCompleted: Bool
    var createdAt: Date
    var notes: String?
    var section: FocusSection?

    init(id: UUID = UUID(), title: String, dueDate: Date, startDate: Date? = nil, isCompleted: Bool = false, createdAt: Date = .now, notes: String? = nil, section: FocusSection? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.startDate = startDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.notes = notes
        self.section = section
    }
}

// MARK: - NotificationManager.swift

import UserNotifications

enum NotificationManager {
    static func requestAuthorization() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if !granted {
                print("Lockheed: notifications not granted")
            }
        } catch {
            print("Lockheed: notification auth error", error.localizedDescription)
        }
    }

    static func schedule(item: FocusItem) {
        let content = UNMutableNotificationContent()
        content.title = "Due: \(item.title)"
        content.body = "It matters. Give it your focus."
        content.sound = .default

        let date = item.dueDate
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { err in
            if let err = err { print("Lockheed: schedule error", err.localizedDescription) }
        }
    }

    static func cancel(item: FocusItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }
}

// MARK: - ConfettiView.swift

import SwiftUI
import CoreGraphics

struct ConfettiView: UXViewRepresentable {
    var intensity: CGFloat = 0.75
    var duration: TimeInterval = 1.5

    #if os(iOS)
    func makeUIView(context: Context) -> UIView { makePlatformView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    #elseif os(macOS)
    func makeNSView(context: Context) -> NSView { makePlatformView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    #endif

    private func makePlatformView() -> UXView {
        let view = UXView()
        DispatchQueue.main.async { emitConfetti(on: view) }
        return view
    }

    private func emitConfetti(on view: UXView) {
        let emitter = CAEmitterLayer()

        #if os(iOS)
        let width  = view.bounds.width
        let height = view.bounds.height
        emitter.emitterPosition = CGPoint(x: width/2, y: -10)         // just above the top edge
        let emissionDown: CGFloat = .pi / 2                            // downwards in iOS coords
        let gravityY: CGFloat = 300                                    // positive -> downward in iOS
        #else
        let width  = view.bounds.size.width
        let height = view.bounds.size.height
        emitter.emitterPosition = CGPoint(x: width/2, y: height + 10)  // just above the top edge (AppKit up axis)
        let emissionDown: CGFloat = -.pi / 2                           // downwards (toward -Y) in AppKit
        let gravityY: CGFloat = -350                                   // negative -> downward in AppKit
        #endif

        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: width, height: 2)

        let colors: [CGColor] = [
            UXColor.systemBlue.cgColor,
            UXColor.systemTeal.cgColor,
            UXColor.systemMint.cgColor,
            UXColor.systemIndigo.cgColor,
            UXColor.systemPurple.cgColor,
            UXColor.systemPink.cgColor
        ]

        func particleImage(kind: Int, color: CGColor) -> CGImage? {
            let size: CGFloat = 12
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: Int(size), height: Int(size),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.setFillColor(color)
            if kind % 2 == 0 {
                ctx.fill(rect)
            } else {
                let path = CGMutablePath()
                path.addEllipse(in: rect)
                ctx.addPath(path)
                ctx.fillPath()
            }
            return ctx.makeImage()
        }

        func ribbonImage(color: CGColor) -> CGImage? {
            let w: CGFloat = 6, h: CGFloat = 28
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: Int(w), height: Int(h),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.setFillColor(color)
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: 3, cornerHeight: 3)
            ctx.addPath(path)
            ctx.fillPath()
            return ctx.makeImage()
        }

        // Base confetti pieces
        var baseCells: [CAEmitterCell] = []
        for i in 0..<6 {
            let cell = CAEmitterCell()
            cell.birthRate = Float(8 * intensity)
            cell.lifetime = 4.0
            cell.lifetimeRange = 1.0
            cell.velocity = 200
            cell.velocityRange = 80
            cell.emissionLongitude = emissionDown
            cell.emissionRange = .pi / 8
            cell.yAcceleration = gravityY
            cell.spin = 3.5
            cell.spinRange = 4
            cell.scale = 0.6
            cell.scaleRange = 0.4
            let color = colors[i % colors.count]
            cell.color = color
            cell.contents = particleImage(kind: i, color: color)
            baseCells.append(cell)
        }

        // Ribbons
        var ribbonCells: [CAEmitterCell] = []
        for i in 0..<4 {
            let ribbon = CAEmitterCell()
            ribbon.birthRate = Float(5 * intensity)
            ribbon.lifetime = 4.5
            ribbon.lifetimeRange = 1.0
            ribbon.velocity = 180
            ribbon.velocityRange = 60
            ribbon.emissionLongitude = emissionDown
            ribbon.emissionRange = .pi / 10
            ribbon.yAcceleration = gravityY
            ribbon.spin = 1.2
            ribbon.spinRange = 1.0
            ribbon.scale = 1.0
            ribbon.scaleRange = 0.2
            let color = colors[i % colors.count]
            ribbon.color = color
            ribbon.contents = ribbonImage(color: color)
            ribbonCells.append(ribbon)
        }

        emitter.emitterCells = baseCells + ribbonCells

        #if os(iOS)
        view.layer.addSublayer(emitter)
        #else
        view.wantsLayer = true
        view.layer?.addSublayer(emitter)
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            emitter.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { emitter.removeFromSuperlayer() }
        }
    }
}

// MARK: - Style Helpers

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 125, 122, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension Color {
    func toHexRGB() -> String? {
        #if os(iOS)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, &g, &b, &a) else { return nil }
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #elseif os(macOS)
        let nsColor = NSColor(self)
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #endif
    }
}

struct Card<Content: View>: View {
    var accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.1), radius: 18, y: 8)
            content
                .padding(18)
        }
        .padding(.horizontal)
    }
}

// MARK: - VisualEffectBlur

struct VisualEffectBlur: UXViewRepresentable {
    #if os(iOS)
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
    #elseif os(macOS)
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
    #endif
}


// MARK: - HeaderBannerView

struct HeaderBannerView: View {
    var height: CGFloat = 180

    var body: some View {
        Group {
            #if os(iOS)
            if UIImage(named: "Header Banner") != nil {
                Image("Header Banner")
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #elseif os(macOS)
            if NSImage(named: "Header Banner") != nil {
                Image("Header Banner")
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Label("Missing HeaderBanner", systemImage: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ContentView.swift

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSection.title) private var sections: [FocusSection]
    @State private var showAddSection = false
    @State private var showAddItemForSection: FocusSection?
    @State private var showConfetti = false
    @State private var isFocusMode = false
    @State private var focusSelection: Int = 0
    @State private var scrollAccum: CGFloat = 0

    private var currentRunningItems: [FocusItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return sections
            .flatMap { $0.items }
            .filter { item in
                guard !item.isCompleted else { return false }
                let startDay: Date = item.startDate.map { cal.startOfDay(for: $0) } ?? today
                let dueDay = cal.startOfDay(for: item.dueDate)
                return (startDay...dueDay).contains(today)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    // Extract the "Add" button so we can reuse it in toolbar cleanly.
    private var addSectionButton: some View {
        Button(action: { showAddSection = true }) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        let bannerHeight: CGFloat = 260

        if isFocusMode {
            VStack(spacing: 12) {
                if currentRunningItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 42, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("No running task right now").font(.title3).bold()
                        Text("Focus Mode hides everything except tasks that are in progress today.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $focusSelection) {
                        ForEach(Array(currentRunningItems.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 12) {
                                Text(item.title)
                                    .font(.largeTitle).bold()
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                HStack(spacing: 16) {
                                    if let start = item.startDate {
                                        Label { Text(start, style: .date) } icon: { Image(systemName: "play.fill") }
                                    }
                                    Label { Text(item.dueDate, style: .date) } icon: { Image(systemName: "stop.fill") }
                                }
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .tag(index)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                    #else
                    .tabViewStyle(.automatic)
                    #endif
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .overlay(ScrollWheelCatcher(onScroll: { deltaY in
                        // Accumulate wheel delta and only switch when passing a threshold
                        let threshold: CGFloat = 30 // larger threshold -> less sensitive
                        scrollAccum += deltaY
                        if scrollAccum <= -threshold {
                            // scroll down -> next
                            focusSelection = min(focusSelection + 1, max(0, currentRunningItems.count - 1))
                            scrollAccum = 0
                        } else if scrollAccum >= threshold {
                            // scroll up -> previous
                            focusSelection = max(focusSelection - 1, 0)
                            scrollAccum = 0
                        }
                    }))
                    #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, bannerHeight)
            .onChange(of: isFocusMode) { old, new in
                if new {
                    focusSelection = 0
                    scrollAccum = 0
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if sections.isEmpty {
                        EmptyState()
                            .padding(.top, 80)
                    } else {
                        ForEach(sections) { section in
                            SectionCard(
                                section: section,
                                onAddItem: { showAddItemForSection = section },
                                onToggleComplete: { item in
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                        item.isCompleted.toggle()
                                        if item.isCompleted { showConfetti = true }
                                    }
                                },
                                onDeleteItem: { item in
                                    NotificationManager.cancel(item: item)
                                    context.delete(item)
                                }
                            )
                        }
                    }
                }
                .padding(.top, bannerHeight)
                .padding(.bottom, 12)
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Lockheed")
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) { addSectionButton }
                    #else
                    ToolbarItem(placement: .automatic) { addSectionButton }
                    #endif
                }
                .task { await NotificationManager.requestAuthorization() }
                .sheet(isPresented: $showAddSection) {
                    AddSectionView { title, colorHex in
                        let section = FocusSection(title: title, accentHex: colorHex)
                        context.insert(section)
                    }
                    .applyIfiOSPresentationDetents()
                }
                .sheet(item: $showAddItemForSection) { section in
                    AddItemView(section: section) { newItem in
                        NotificationManager.schedule(item: newItem)
                    }
                    .applyIfiOSPresentationDetents()
                }
                .overlay(alignment: .top) {
                    if showConfetti {
                        ConfettiView()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation { showConfetti = false }
                                }
                            }
                    }
                }
                .overlay(alignment: .top) {
                    HeaderBannerView(height: 260)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                        .zIndex(0)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        Text(isFocusMode ? "Focus" : "Add")
                            .font(.callout).fontWeight(.semibold)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                        Toggle("", isOn: $isFocusMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .zIndex(2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBlur().ignoresSafeArea())
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}


extension View {
    @ViewBuilder
    func applyIfiOSPresentationDetents() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium])
        #else
        self
        #endif
    }
}

// MARK: - Empty

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(Font.system(size: 52, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text("What truly matters.")
                .font(.title2).fontWeight(.semibold)
            Text("Create sections for this week or quarter, then add the few tasks that move the needle.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - SectionCard

struct SectionCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var section: FocusSection

    var onAddItem: () -> Void
    var onToggleComplete: (FocusItem) -> Void
    var onDeleteItem: (FocusItem) -> Void

    var body: some View {
        Card(accent: Color(hex: section.accentHex)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(section.title)
                        .font(.title3).fontWeight(.semibold)
                    Spacer()
                    Menu {
                        Button("Add Task", systemImage: "plus", action: onAddItem)
                        Divider()
                        Button(role: .destructive) {
                            context.delete(section)
                        } label: { Label("Delete Section", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(Font.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if section.items.isEmpty {
                    Button(action: onAddItem) {
                        Label("Add a task", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: section.accentHex))
                    .controlSize(.small)
                } else {
                    VStack(spacing: 8) {
                        ForEach(section.items.sorted(by: { $0.dueDate < $1.dueDate })) { item in
                            ItemRow(item: item,
                                    accent: Color(hex: section.accentHex),
                                    toggle: { onToggleComplete(item) },
                                    delete: { onDeleteItem(item) })
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ItemRow

struct ItemRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: FocusItem

    var accent: Color
    var toggle: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(Font.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .tint(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .strikethrough(item.isCompleted, pattern: .solid, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                Text(item.dueDate, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit", systemImage: "pencil") {
                    // Minimal: edit inline by nudging date +1h for demo; extend with a proper sheet if desired.
                    withAnimation { item.dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: item.dueDate) ?? item.dueDate }
                    NotificationManager.cancel(item: item)
                    NotificationManager.schedule(item: item)
                }
                Button("Copy ID", systemImage: "doc.on.doc") {
                    #if os(iOS)
                    UIPasteboard.general.string = item.id.uuidString
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.id.uuidString, forType: .string)
                    #endif
                }
                Divider()
                Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Font.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - AddSectionView

struct AddSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var accentHex: String = "#7D7AFF"
    @State private var accentColor: Color = Color(hex: "#7D7AFF")

    var onCreate: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section() {
                    TextField("Title", text: $title)
                    ColorPicker("Accent", selection: $accentColor, supportsOpacity: false)
                }
            }
            .navigationTitle("Add Section")
            .onAppear {
                accentColor = Color(hex: accentHex)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let hex = accentColor.toHexRGB() ?? accentHex
                        onCreate(title.trimmingCharacters(in: .whitespacesAndNewlines), hex)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - AddItemView

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var section: FocusSection
    var onCreate: (FocusItem) -> Void

    @State private var title: String = ""
    @State private var dueDate: Date = Date()
    @State private var notes: String = ""
    @State private var startDate: Date? = nil

    private func nextEightAM(from date: Date = .now) -> Date {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        var eightAM = cal.date(byAdding: DateComponents(hour: 8), to: startOfDay) ?? date
        if eightAM <= date { // if 8AM today has passed, choose tomorrow 8AM
            let tomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
            eightAM = cal.date(byAdding: DateComponents(hour: 8), to: tomorrow) ?? date
        }
        return eightAM
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Task in \(section.title)") {
                    TextField("Task", text: $title)
                    Toggle("Start time", isOn: Binding(
                        get: { startDate != nil },
                        set: { newValue in
                            if newValue {
                                if startDate == nil { startDate = Date() }
                            } else {
                                startDate = nil
                            }
                        }
                    ))
                    if startDate != nil {
                        let startBinding = Binding<Date>(
                            get: { startDate ?? Date() },
                            set: { startDate = $0 }
                        )
                        DatePicker("Start", selection: startBinding, displayedComponents: [.date, .hourAndMinute])
                    }
                    DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                .onChange(of: startDate) { oldValue, newValue in
                    if let s = newValue, dueDate < s { dueDate = s }
                }
                .onChange(of: dueDate) { oldValue, newValue in
                    if let s = startDate, newValue < s { startDate = newValue }
                }
            }
            .navigationTitle("Add Task")
            .onAppear {
                let eight = nextEightAM()
                startDate = eight
                dueDate = eight
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = FocusItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), dueDate: dueDate, startDate: startDate, notes: notes.isEmpty ? nil : notes, section: section)
                        section.items.append(item)
                        onCreate(item)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Sample Preview Data

#if DEBUG
struct PreviewBootstrap: ViewModifier {
    let context: ModelContext
    func body(content: Content) -> some View { content }
    init(_ container: ModelContainer) {
        context = ModelContext(container)
        // Seed data
        let visa = FocusSection(title: "VISA Interview", accentHex: "#00C2FF")
        let midterms = FocusSection(title: "Midterms", accentHex: "#7D7AFF")
        let finals = FocusSection(title: "Finals", accentHex: "#FF6B6B")
        let putnam = FocusSection(title: "Putnam", accentHex: "#34C759")

        let items: [(FocusSection,String,Int)] = [
            (visa, "Mock system design dry‑run", 48),
            (midterms, "CSE 100R next week", 72),
            (midterms, "CSE 105 following week", 168),
            (midterms, "CSE 101 following week", 168),
            (finals, "Compile formula sheet", 300),
            (putnam, "Two problems daily", 24)
        ]
        for (section, title, hours) in items {
            let due = Calendar.current.date(byAdding: .hour, value: hours, to: .now) ?? .now
            let it = FocusItem(title: title, dueDate: due, section: section)
            section.items.append(it)
        }
        context.insert(visa); context.insert(midterms); context.insert(finals); context.insert(putnam)
        try? context.save()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let schema = Schema([FocusSection.self, FocusItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        return ContentView()
            .modelContainer(container)
            .modifier(PreviewBootstrap(container))
    }
}
#endif

