import SwiftUI
import UIKit
import EventKit
import UniformTypeIdentifiers

// MARK: - PIN-Sperre

struct ParentGate: View {
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @State private var entered = ""
    @State private var wrong = false
    @State private var unlocked = false

    var body: some View {
        if unlocked {
            ParentView(onClose: onClose)
        } else {
            VStack(spacing: 18) {
                Text("Eltern-PIN").font(.largeTitle.bold())
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 3)
                            .background(Circle().fill(i < entered.count ? Color.primary : Color.clear))
                            .frame(width: 20, height: 20)
                    }
                }
                Text(wrong ? "Falsche PIN" : " ")
                    .font(.headline)
                    .foregroundStyle(.red)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 12), count: 3), spacing: 12) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "x", "0", "<"], id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "x" { Image(systemName: "xmark") }
                                else if key == "<" { Image(systemName: "delete.left") }
                                else { Text(key) }
                            }
                            .font(.title.weight(.bold))
                            .frame(width: 84, height: 72)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color.chip))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "x" ? "Abbrechen" : (key == "<" ? "Löschen" : key))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.page.ignoresSafeArea())
            .sensoryFeedback(.error, trigger: wrong) { _, new in new }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "x": onClose()
        case "<": entered = String(entered.dropLast())
        default:
            guard entered.count < 4 else { return }
            entered += key
            wrong = false
            if entered.count == 4 {
                if entered == store.data.setup.pin {
                    unlocked = true
                } else {
                    wrong = true
                    entered = ""
                }
            }
        }
    }
}

struct ParentView: View {
    let onClose: () -> Void

    var body: some View {
        TabView {
            TasksAdmin(onClose: onClose)
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
            KidsAdmin(onClose: onClose)
                .tabItem { Label("Kinder", systemImage: "person.2.fill") }
            CalendarAdmin(onClose: onClose)
                .tabItem { Label("Kalender", systemImage: "calendar") }
            SettingsAdmin(onClose: onClose)
                .tabItem { Label("PIN & Sicherung", systemImage: "lock.shield") }
        }
    }
}

private struct DoneButton: ToolbarContent {
    let onClose: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fertig", action: onClose).bold()
        }
    }
}

// MARK: - Aufgaben

struct TasksAdmin: View {
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @State private var kidID = ""
    @State private var editing: FamilyTask?

    var body: some View {
        NavigationStack {
            List {
                if store.kids.isEmpty {
                    Text("Lege zuerst unter „Kinder“ ein Kind an.")
                } else {
                    Section {
                        Picker("Kind", selection: $kidID) {
                            ForEach(store.kids) { k in Text(k.name).tag(k.id) }
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(Slot.allCases) { s in
                        Section {
                            let ts = store.slotTasks(kid: kidID, slot: s)
                            if ts.isEmpty {
                                Text("Noch keine Aufgaben").foregroundStyle(.secondary)
                            }
                            ForEach(ts) { t in
                                Button { editing = t } label: {
                                    HStack(spacing: 12) {
                                        TaskIcon(icon: t.icon, size: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title).font(.headline)
                                            Text(t.dayLabel + (t.kids.count > 1 ? " · \(t.kids.count) Kinder" : ""))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .onMove { from, to in
                                store.move(kid: kidID, slot: s, from: from, to: to)
                            }
                        } header: {
                            Label(s.label, systemImage: s.symbol).foregroundStyle(s.color)
                        }
                    }
                }
            }
            .navigationTitle("Aufgaben")
            .toolbar {
                DoneButton(onClose: onClose)
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        var t = FamilyTask()
                        t.kids = [kidID]
                        editing = t
                    } label: {
                        Label("Neue Aufgabe", systemImage: "plus")
                    }
                    .disabled(store.kids.isEmpty)
                }
            }
            .sheet(item: $editing) { t in
                TaskEditor(task: t, isNew: !store.data.setup.tasks.contains { $0.id == t.id })
            }
            .onAppear {
                if !store.kids.contains(where: { $0.id == kidID }) {
                    kidID = store.kids.first?.id ?? ""
                }
            }
        }
    }
}

struct TaskEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var task: FamilyTask
    @State private var oneDay: Bool
    @State private var day: Date
    @State private var confirmDelete = false
    let isNew: Bool

    init(task: FamilyTask, isNew: Bool) {
        _task = State(initialValue: task)
        _oneDay = State(initialValue: !task.date.isEmpty)
        _day = State(initialValue: Day.date(task.date) ?? Date())
        self.isNew = isNew
    }

    private var valid: Bool {
        !task.title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !task.kids.isEmpty &&
        (oneDay || !task.days.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("z. B. Zähne putzen", text: $task.title)
                        .font(.title3)
                }
                Section("Tageszeit") {
                    Picker("Tageszeit", selection: $task.slot) {
                        ForEach(Slot.allCases) { s in Text(s.label).tag(s) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Für") {
                    ForEach(store.kids) { k in
                        Toggle(k.name, isOn: Binding(
                            get: { task.kids.contains(k.id) },
                            set: { on in
                                if on {
                                    if !task.kids.contains(k.id) { task.kids.append(k.id) }
                                } else {
                                    task.kids.removeAll { id in id == k.id }
                                }
                            }
                        ))
                    }
                }
                Section("Wann") {
                    Toggle("Nur an einem bestimmten Datum", isOn: $oneDay)
                    if oneDay {
                        DatePicker("Datum", selection: $day, displayedComponents: .date)
                    } else {
                        HStack(spacing: 6) {
                            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in
                                let on = task.days.contains(d)
                                Button {
                                    if on { task.days.removeAll { x in x == d } } else { task.days.append(d) }
                                } label: {
                                    Text(Day.short[d])
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.accentColor : Color.chip))
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Button("Täglich") { task.days = [0, 1, 2, 3, 4, 5, 6] }
                            Button("Mo–Fr") { task.days = [1, 2, 3, 4, 5] }
                            Button("Wochenende") { task.days = [6, 0] }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("Bild") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                        ForEach(Palette.emojis, id: \.self) { e in
                            Button { task.icon = e } label: {
                                TaskIcon(icon: e, size: 30)
                                    .frame(width: 52, height: 52)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(task.icon == e ? Color.accentColor.opacity(0.25) : Color.chip))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !isNew {
                    Section {
                        Button("Aufgabe löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Neue Aufgabe" : "Aufgabe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!valid)
                }
            }
            .confirmationDialog("Aufgabe wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    let id = task.id
                    store.update { d in d.setup.tasks.removeAll { t in t.id == id } }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        var t = task
        t.title = t.title.trimmingCharacters(in: .whitespaces)
        if oneDay {
            t.date = Day.key(day)
            t.days = []
        } else {
            t.date = ""
        }
        store.update { d in
            if let i = d.setup.tasks.firstIndex(where: { x in x.id == t.id }) {
                d.setup.tasks[i] = t
            } else {
                d.setup.tasks.append(t)
            }
        }
        dismiss()
    }
}

// MARK: - Kinder

struct KidsAdmin: View {
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.kids) { k in KidRow(kid: k) }
                        .onDelete(perform: delete)
                } footer: {
                    Text("Zum Entfernen nach links wischen. Dabei verschwinden auch die Aufgaben, die nur für dieses Kind galten.")
                }
                Section("Kind hinzufügen") {
                    HStack {
                        TextField("Name", text: $newName)
                            .onSubmit(add)
                        Button("Hinzufügen", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Kinder")
            .toolbar { DoneButton(onClose: onClose) }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let color = Palette.kidColors[store.kids.count % Palette.kidColors.count]
        store.update { d in d.setup.kids.append(Kid(name: name, color: color)) }
        newName = ""
    }

    private func delete(_ offsets: IndexSet) {
        let ids = offsets.map { store.kids[$0].id }
        store.update { d in
            d.setup.kids.removeAll { k in ids.contains(k.id) }
            for i in d.setup.tasks.indices {
                d.setup.tasks[i].kids.removeAll { id in ids.contains(id) }
            }
            d.setup.tasks.removeAll { t in t.kids.isEmpty }
        }
    }
}

struct KidRow: View {
    let kid: Kid
    @Environment(Store.self) private var store
    @State private var name: String

    init(kid: Kid) {
        self.kid = kid
        _name = State(initialValue: kid.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $name)
                .font(.title3.weight(.semibold))
                .onChange(of: name) { commit() }
            HStack(spacing: 10) {
                ForEach(Palette.kidColors, id: \.self) { hex in
                    Button {
                        store.update { d in
                            if let i = d.setup.kids.firstIndex(where: { k in k.id == kid.id }) {
                                d.setup.kids[i].color = hex
                            }
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: kid.color == hex ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Farbe")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != kid.name else { return }
        store.update { d in
            if let i = d.setup.kids.firstIndex(where: { k in k.id == kid.id }) {
                d.setup.kids[i].name = n
            }
        }
    }
}

// MARK: - Kalender

struct CalendarAdmin: View {
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var cal
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if cal.authorized {
                        Label("Zugriff auf Kalender erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if cal.status == .notDetermined {
                        Button("Zugriff auf Kalender erlauben") {
                            Task { await cal.requestAccess() }
                        }
                    } else {
                        Text("Der Zugriff auf die Kalender ist nicht erlaubt.")
                        Button("Einstellungen öffnen") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                        }
                    }
                } footer: {
                    Text("Termine kommen direkt aus den Kalendern dieses Geräts, auch aus iCloud. Neue Termine erscheinen sofort.")
                }

                if cal.authorized {
                    Section("Angezeigte Kalender") {
                        ForEach(cal.calendars, id: \.calendarIdentifier) { c in
                            Toggle(isOn: binding(for: c.calendarIdentifier)) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(cgColor: c.cgColor)).frame(width: 12, height: 12)
                                    VStack(alignment: .leading) {
                                        Text(c.title)
                                        Text(c.source.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kalender")
            .toolbar { DoneButton(onClose: onClose) }
            .onAppear { cal.refreshStatus() }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.data.calendarIDs?.contains(id) ?? true },
            set: { on in
                var ids = Set(store.data.calendarIDs ?? cal.calendars.map(\.calendarIdentifier))
                if on { ids.insert(id) } else { ids.remove(id) }
                store.update { d in d.calendarIDs = Array(ids) }
            }
        )
    }
}

// MARK: - PIN & Sicherung

struct SettingsAdmin: View {
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @State private var newPin = ""
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Neue PIN (4 Ziffern)", text: $newPin)
                        .keyboardType(.numberPad)
                    Button("PIN speichern") {
                        let p = newPin
                        store.update { d in d.setup.pin = p }
                        newPin = ""
                        message = "PIN gespeichert"
                    }
                    .disabled(newPin.count != 4 || !newPin.allSatisfy(\.isNumber))
                } header: {
                    Text("Eltern-PIN")
                } footer: {
                    Text("Die PIN hält die Kinder vom Eltern-Bereich fern.")
                }

                Section {
                    Button("Sicherung erstellen") {
                        do { backupURL = try store.makeBackupFile() }
                        catch { message = "Die Sicherung konnte nicht erstellt werden." }
                    }
                    if let url = backupURL {
                        ShareLink("Sicherung teilen oder in „Dateien“ sichern", item: url)
                    }
                    Button("Sicherung laden") { importing = true }
                } header: {
                    Text("Datensicherung")
                } footer: {
                    Text("Auch Sicherungen aus der Web-Version lassen sich hier laden. Beim Laden werden Kinder, Aufgaben und Häkchen ersetzt.")
                }
            }
            .navigationTitle("PIN & Sicherung")
            .toolbar { DoneButton(onClose: onClose) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    do {
                        try store.importBackup(from: url)
                        message = "Sicherung geladen"
                    } catch {
                        message = "Das ist keine Familienzeit-Sicherung."
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
