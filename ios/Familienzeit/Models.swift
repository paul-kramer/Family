import SwiftUI
import UIKit

// MARK: - Tageszeiten

enum Slot: String, Codable, CaseIterable, Identifiable {
    case morgens, nachmittags, abends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morgens: return "Morgens"
        case .nachmittags: return "Nachmittags"
        case .abends: return "Abends"
        }
    }

    var symbol: String {
        switch self {
        case .morgens: return "sunrise.fill"
        case .nachmittags: return "sun.max.fill"
        case .abends: return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morgens: return Color(hex: "#F29D38")
        case .nachmittags: return Color(hex: "#3FA46A")
        case .abends: return Color(hex: "#5B5BD6")
        }
    }

    var soft: Color { color.opacity(0.18) }

    static var current: Slot {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return .morgens }
        if h < 17 { return .nachmittags }
        return .abends
    }
}

// MARK: - Daten (gleiches Format wie die Sicherung der Web-Version)

struct Kid: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var color: String = "#2F6FD6"

    var swiftColor: Color { Color(hex: color) }
}

extension Kid {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#2F6FD6"
    }
}

/// Wochentage wie in JavaScript: 0 = Sonntag … 6 = Samstag.
struct FamilyTask: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = ""
    var icon: String = "⭐"
    var slot: Slot = .morgens
    var kids: [String] = []
    var days: [Int] = [1, 2, 3, 4, 5]
    var date: String = ""          // "yyyy-MM-dd" für einmalige Aufgaben, sonst leer
    var order: Double = Date().timeIntervalSince1970
    /// Reihenfolge je Kind (Kind-ID → Position); fehlt ein Eintrag, gilt `order`.
    var orders: [String: Double] = [:]

    func position(for kid: String) -> Double { orders[kid] ?? order }

    var dayLabel: String {
        if !date.isEmpty, let d = Day.date(date) {
            return "nur am " + d.formatted(.dateTime.day().month(.twoDigits))
        }
        let s = days.sorted { ($0 + 6) % 7 < ($1 + 6) % 7 }
        if s.count == 7 { return "täglich" }
        if s == [1, 2, 3, 4, 5] { return "Mo–Fr" }
        if s == [6, 0] { return "Wochenende" }
        if s.isEmpty { return "kein Tag" }
        return s.map { Day.short[$0] }.joined(separator: ", ")
    }
}

extension FamilyTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "⭐"
        slot = (try? c.decode(Slot.self, forKey: .slot)) ?? .morgens
        kids = try c.decodeIfPresent([String].self, forKey: .kids) ?? []
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? []
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        orders = (try? c.decodeIfPresent([String: Double].self, forKey: .orders)) ?? [:]
    }
}

struct Setup: Codable {
    var pin: String = "0000"
    var kids: [Kid] = []
    var tasks: [FamilyTask] = []
}

extension Setup {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? "0000"
        kids = try c.decodeIfPresent([Kid].self, forKey: .kids) ?? []
        tasks = try c.decodeIfPresent([FamilyTask].self, forKey: .tasks) ?? []
    }
}

struct AppData: Codable {
    var setup: Setup
    /// Datum → ("kindId_aufgabeId" → erledigt)
    var done: [String: [String: Bool]] = [:]
    /// Ausgewählte Kalender; nil = alle Kalender anzeigen
    var calendarIDs: [String]? = nil
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setup = try c.decode(Setup.self, forKey: .setup)
        done = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .done) ?? [:]
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs)
    }

    static var sample: AppData {
        let both = ["moritz", "kind2"]
        let all = [0, 1, 2, 3, 4, 5, 6]
        return AppData(setup: Setup(
            pin: "0000",
            kids: [
                Kid(id: "moritz", name: "Moritz", color: "#2F6FD6"),
                Kid(id: "kind2", name: "Kind 2", color: "#E0603A"),
            ],
            tasks: [
                FamilyTask(id: "t1", title: "Anziehen", icon: "👕", slot: .morgens, kids: both, days: [1, 2, 3, 4, 5], order: 1),
                FamilyTask(id: "t2", title: "Frühstücken", icon: "🥣", slot: .morgens, kids: both, days: all, order: 2),
                FamilyTask(id: "t3", title: "Zähne putzen", icon: "🪥", slot: .morgens, kids: both, days: all, order: 3),
                FamilyTask(id: "t4", title: "Ranzen mitnehmen", icon: "🎒", slot: .morgens, kids: ["moritz"], days: [1, 2, 3, 4, 5], order: 4),
                FamilyTask(id: "t5", title: "Eishockey-Tasche packen", icon: "🏒", slot: .nachmittags, kids: ["moritz"], days: [2, 4, 5], order: 5),
                FamilyTask(id: "t6", title: "10 Minuten lesen", icon: "📖", slot: .nachmittags, kids: ["moritz"], days: [1, 2, 3, 4, 5], order: 6),
                FamilyTask(id: "t7", title: "Spielzeug aufräumen", icon: "🧸", slot: .nachmittags, kids: ["kind2"], days: all, order: 7),
                FamilyTask(id: "t8", title: "Schlafanzug anziehen", icon: "🛏️", slot: .abends, kids: both, days: all, order: 8),
                FamilyTask(id: "t9", title: "Zähne putzen", icon: "🪥", slot: .abends, kids: both, days: all, order: 9),
            ]
        ))
    }
}

/// Format der Datensicherung (kompatibel zur Web-Version).
struct Backup: Codable {
    var app: String = "familienzeit"
    var saved: String = ""
    var setup: Setup
    var done: [String: [String: Bool]]? = nil
}

// MARK: - Hilfen

enum Day {
    static let short = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let long = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                         "August", "September", "Oktober", "November", "Dezember"]

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ s: String) -> Date? { fmt.date(from: s) }
    static func weekday(_ d: Date) -> Int { Calendar.current.component(.weekday, from: d) - 1 }
    static func dayOfMonth(_ d: Date) -> Int { Calendar.current.component(.day, from: d) }

    static func weekStart(_ d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? Calendar.current.startOfDay(for: d)
    }

    static func add(_ days: Int, to d: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: d) ?? d
    }

    static func longText(_ d: Date) -> String {
        "\(long[weekday(d)]), \(dayOfMonth(d)). \(months[Calendar.current.component(.month, from: d) - 1])"
    }
}

/// Zeigt ein Aufgaben-Symbol: Emoji oder eigenes Symbol (z. B. "svg:hockey").
struct TaskIcon: View {
    let icon: String
    var size: CGFloat = 24

    var body: some View {
        if icon == "svg:hockey" {
            Image(systemName: "figure.hockey")
                .font(.system(size: size * 0.9, weight: .semibold))
                .foregroundStyle(Color(hex: "#E0603A"))
                .frame(width: size * 1.2, height: size * 1.2)
                .accessibilityLabel("Eishockeyspieler")
        } else {
            Text(icon.isEmpty ? "⭐" : icon).font(.system(size: size))
        }
    }
}

enum Palette {
    static let kidColors = ["#2F6FD6", "#E0603A", "#2E9E5B", "#B04AC9", "#D69A12", "#1F9AA8"]
    static let emojis = ["🪥", "👕", "🧦", "🛏️", "🥣", "🍎", "🎒", "📚", "✏️", "🧮", "🎹", "🏒", "⚽", "🚿", "🛁",
                         "🧸", "🧹", "🍽️", "🐶", "🌱", "💊", "📖", "🧥", "👟", "🚲", "🎨", "📞", "⏰",
                         "svg:hockey", "⛸️", "📦", "🧺", "🗃️", "📺", "🎮", "🙏", "⭐"]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count != 6 { s = "2F6FD6" }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    static let card = Color(uiColor: .systemBackground)
    static let page = Color(uiColor: .systemGroupedBackground)
    static let chip = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
}
