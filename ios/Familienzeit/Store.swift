import SwiftUI
import EventKit

/// Kinder, Aufgaben und Häkchen. Gespeichert als JSON-Datei in der App.
@MainActor
@Observable
final class Store {
    private(set) var data: AppData
    private let url: URL

    init() {
        url = URL.documentsDirectory.appending(path: "familienzeit.json")
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData.sample
        }
    }

    var kids: [Kid] { data.setup.kids }

    func update(_ change: (inout AppData) -> Void) {
        change(&data)
        save()
    }

    private func save() {
        do {
            let raw = try JSONEncoder().encode(data)
            try raw.write(to: url, options: .atomic)
        } catch {
            print("Speichern fehlgeschlagen: \(error)")
        }
    }

    // MARK: Aufgaben

    func tasks(for kidID: String, on date: Date, slot: Slot) -> [FamilyTask] {
        let key = Day.key(date)
        let wd = Day.weekday(date)
        return data.setup.tasks
            .filter { t in
                t.kids.contains(kidID) && t.slot == slot &&
                (t.date.isEmpty ? t.days.contains(wd) : t.date == key)
            }
            .sorted { $0.position(for: kidID) < $1.position(for: kidID) }
    }

    /// Alle Aufgaben eines Kindes in einer Tageszeit, in seiner Reihenfolge.
    func slotTasks(kid: String, slot: Slot) -> [FamilyTask] {
        data.setup.tasks
            .filter { $0.kids.contains(kid) && $0.slot == slot }
            .sorted { $0.position(for: kid) < $1.position(for: kid) }
    }

    /// Reihenfolge nur für dieses Kind ändern.
    func move(kid: String, slot: Slot, from: IndexSet, to: Int) {
        var ids = slotTasks(kid: kid, slot: slot).map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        update { d in
            for (n, id) in ids.enumerated() {
                if let i = d.setup.tasks.firstIndex(where: { t in t.id == id }) {
                    d.setup.tasks[i].orders[kid] = Double(n)
                }
            }
        }
    }

    func isDone(_ date: Date, kid: String, task: String) -> Bool {
        data.done[Day.key(date)]?[kid + "_" + task] ?? false
    }

    func toggle(_ date: Date, kid: String, task: String) {
        let key = Day.key(date)
        let item = kid + "_" + task
        update { d in
            var day = d.done[key] ?? [:]
            day[item] = !(day[item] ?? false)
            d.done[key] = day
            let limit = Day.key(Day.add(-60, to: Date()))
            d.done = d.done.filter { entry in entry.key >= limit }
        }
    }

    func stats(kid: String, date: Date, slot: Slot) -> (done: Int, total: Int) {
        let ts = tasks(for: kid, on: date, slot: slot)
        let done = ts.filter { isDone(date, kid: kid, task: $0.id) }.count
        return (done: done, total: ts.count)
    }

    func totalStats(date: Date, slot: Slot) -> (done: Int, total: Int) {
        var done = 0
        var total = 0
        for k in kids {
            let s = stats(kid: k.id, date: date, slot: slot)
            done += s.done
            total += s.total
        }
        return (done: done, total: total)
    }

    // MARK: Sicherung

    func makeBackupFile() throws -> URL {
        let backup = Backup(saved: ISO8601DateFormatter().string(from: Date()), setup: data.setup, done: data.done)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = FileManager.default.temporaryDirectory
            .appending(path: "familienzeit-sicherung-\(Day.key(Date())).json")
        try enc.encode(backup).write(to: file, options: .atomic)
        return file
    }

    func importBackup(from file: URL) throws {
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: file)
        let backup = try JSONDecoder().decode(Backup.self, from: raw)
        update { d in
            d.setup = backup.setup
            d.done = backup.done ?? [:]
        }
    }
}

/// Liest Termine direkt aus den Kalendern des Geräts (inkl. iCloud).
@MainActor
@Observable
final class CalendarService {
    let eventStore = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [EKCalendar] = []
    private(set) var changeToken = 0

    var authorized: Bool { status == .fullAccess }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        refreshStatus()
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    func reload() {
        calendars = authorized
            ? eventStore.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            : []
        changeToken += 1
    }

    func events(on day: Date, calendarIDs: [String]?) -> [EKEvent] {
        _ = changeToken
        guard authorized else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Day.add(1, to: start)
        var selected: [EKCalendar]? = nil
        if let ids = calendarIDs {
            selected = calendars.filter { ids.contains($0.calendarIdentifier) }
            if selected?.isEmpty == true { return [] }
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        return eventStore.events(matching: predicate).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.startDate < b.startDate
        }
    }
}
