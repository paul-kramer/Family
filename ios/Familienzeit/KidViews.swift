import SwiftUI
import UIKit
import EventKit

@main
struct FamilienzeitApp: App {
    @State private var store = Store()
    @State private var calendar = CalendarService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(calendar)
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var cal
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var date = Date()
    @State private var slot = Slot.current
    @State private var showParent = false
    @State private var lastToday = Day.key(Date())

    var body: some View {
        Group {
            if hSize == .compact {
                ScrollView { content(compact: true) }
            } else {
                content(compact: false)
            }
        }
        .background(Color.page.ignoresSafeArea())
        .fullScreenCover(isPresented: $showParent) {
            ParentGate { showParent = false }
        }
        .task {
            cal.refreshStatus()
            if cal.status == .notDetermined { await cal.requestAccess() }
        }
        .onChange(of: phase) {
            guard phase == .active else { return }
            cal.refreshStatus()
            let today = Day.key(Date())
            if today != lastToday {
                lastToday = today
                date = Date()
                slot = .current
            }
        }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(Day.longText(Date()))
                    .font(.title2.weight(.bold))
                Spacer()
                Button { showParent = true } label: {
                    Label("Eltern", systemImage: "lock.fill").font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            // Die Woche bekommt gut ein Fünftel der Bildschirmhöhe.
            WeekBar(date: $date)
                .containerRelativeFrame(.vertical) { h, _ in
                    compact ? 130 : min(max(h * 0.22, 130), 210)
                }

            HStack(spacing: compact ? 8 : 10) {
                ForEach(Slot.allCases) { s in
                    SlotButton(slot: s, selected: slot == s, date: date) { select(s) }
                }
            }
            .frame(height: compact ? 84 : 66)

            if store.kids.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch keine Kinder angelegt").font(.title2.bold())
                    Text("Lege im Eltern-Bereich die Kinder und ihre Aufgaben an. Start-PIN: 0000")
                        .foregroundStyle(.secondary)
                    Button("Eltern-Bereich öffnen") { showParent = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compact {
                VStack(spacing: 10) {
                    ForEach(store.kids) { k in
                        KidColumn(kid: k, date: date, slot: slot, scrolls: false)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.kids) { k in
                        KidColumn(kid: k, date: date, slot: slot, scrolls: true)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func select(_ s: Slot) {
        withAnimation(.snappy) { slot = s }
    }
}

// MARK: - Woche

struct WeekBar: View {
    @Binding var date: Date
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var cal

    var body: some View {
        let start = Day.weekStart(date)
        HStack(spacing: 6) {
            arrow("chevron.left") { date = Day.add(-7, to: date) }
            ForEach(0..<7, id: \.self) { i in
                let d = Day.add(i, to: start)
                dayButton(d)
            }
            arrow("chevron.right") { date = Day.add(7, to: date) }
        }
    }

    private func dayButton(_ d: Date) -> some View {
        let selected = Calendar.current.isDate(d, inSameDayAs: date)
        let isToday = Calendar.current.isDateInToday(d)
        let events = cal.events(on: d, calendarIDs: store.data.calendarIDs)
        return Button { date = d } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Day.short[Day.weekday(d)].uppercased())
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Text("\(Day.dayOfMonth(d))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        ForEach(Slot.allCases) { s in
                            let st = store.totalStats(date: d, slot: s)
                            if st.total > 0 {
                                Circle()
                                    .fill(st.done == st.total ? Color.green : Color(uiColor: .systemGray4))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                            VStack(alignment: .leading, spacing: 0) {
                                if !e.isAllDay {
                                    Text(e.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2.weight(.heavy).monospacedDigit())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(e.title ?? "Termin")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(cgColor: e.calendar.cgColor).opacity(e.isAllDay ? 0.28 : 0.14))
                            )
                        }
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(isToday ? Color.accentColor.opacity(0.08) : Color.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Day.long[Day.weekday(d)]) \(Day.dayOfMonth(d)), \(events.count) Termine")
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 36)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.card))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tageszeiten

struct SlotButton: View {
    let slot: Slot
    let selected: Bool
    let date: Date
    let action: () -> Void
    @Environment(Store.self) private var store

    var body: some View {
        let st = store.totalStats(date: date, slot: slot)
        let allDone = st.total > 0 && st.done == st.total
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    icon
                    VStack(alignment: .leading, spacing: 0) {
                        Text(slot.label).font(.title3.weight(.heavy)).lineLimit(1)
                        statusText(st, allDone)
                    }
                }
                VStack(spacing: 2) {
                    icon
                    Text(slot.label).font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    statusText(st, allDone)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(slot.soft))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? slot.color : Color.clear, lineWidth: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var icon: some View {
        Image(systemName: slot.symbol)
            .font(.system(size: 24))
            .foregroundStyle(slot.color)
    }

    private func statusText(_ st: (done: Int, total: Int), _ allDone: Bool) -> some View {
        Text(st.total == 0 ? "frei" : (allDone ? "Alles erledigt" : "\(st.done) von \(st.total)"))
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(allDone ? Color.green : Color.secondary)
            .lineLimit(1)
    }
}

// MARK: - Kinderspalte

struct KidColumn: View {
    let kid: Kid
    let date: Date
    let slot: Slot
    let scrolls: Bool
    @Environment(Store.self) private var store

    var body: some View {
        let tasks = store.tasks(for: kid.id, on: date, slot: slot)
        let doneCount = tasks.filter { store.isDone(date, kid: kid.id, task: $0.id) }.count
        let allDone = !tasks.isEmpty && doneCount == tasks.count

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(kid.name.prefix(1)).uppercased())
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(kid.swiftColor))
                Text(kid.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(doneCount)/\(tasks.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(allDone ? Color.green : Color.secondary)
                }
            }

            if scrolls {
                ScrollView { list(tasks, allDone) }
            } else {
                list(tasks, allDone)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.card))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(kid.swiftColor)
                .frame(height: 6)
        }
    }

    private func list(_ tasks: [FamilyTask], _ allDone: Bool) -> some View {
        VStack(spacing: 6) {
            if tasks.isEmpty {
                Text("\(slot.label) ist nichts geplant.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 2, dash: [6])))
            } else {
                if allDone {
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill").font(.title3).foregroundStyle(.yellow)
                            .symbolEffect(.bounce, value: allDone)
                        Text("Super, \(kid.name)!").font(.headline.weight(.heavy))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 14).fill(slot.soft))
                }
                ForEach(tasks) { t in
                    TaskRow(task: t, done: store.isDone(date, kid: kid.id, task: t.id), slot: slot) {
                        withAnimation(.snappy) { store.toggle(date, kid: kid.id, task: t.id) }
                    }
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: FamilyTask
    let done: Bool
    let slot: Slot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(task.icon)
                    .font(.system(size: 24))
                    .frame(width: 32)
                Text(task.title)
                    .font(.headline.weight(.heavy))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(done ? slot.color : Color.clear)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(slot.color, lineWidth: 3)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .transition(.scale)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(done ? slot.soft : Color.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(done ? Color.clear : Color.hairline, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
