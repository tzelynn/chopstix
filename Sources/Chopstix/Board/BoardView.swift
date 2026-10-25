import SwiftUI

/// The app's main window: every note, laid out like a noodle-shop menu.
struct BoardView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case everything = "everything", onScreen = "on screen", inMenu = "in the menu"
        var id: Self { self }

        func includes(_ note: Note) -> Bool {
            switch self {
            case .everything: true
            case .onScreen: note.isOnScreen
            case .inMenu: !note.isOnScreen
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .everything
    @State private var editing: EditTarget?

    struct EditTarget: Identifiable {
        let id: UUID
        var autofocus = false
    }

    private var visibleNotes: [Note] {
        model.notes.filter(filter.includes).sorted { $0.number < $1.number }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MenuMasthead()
                    .padding(.top, 34)

                controls
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                if visibleNotes.isEmpty {
                    EmptyMenu(filter: filter) { orderNote(onScreen: false) }
                        .padding(.top, 50)
                } else {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        ForEach(Flavor.allCases) { flavor in
                            let notes = visibleNotes.filter { $0.flavor == flavor }
                            if !notes.isEmpty {
                                MenuSection(flavor: flavor, notes: notes, open: open)
                            }
                        }
                    }
                    .padding(.top, 18)
                }

                MenuFooter()
                    .padding(.top, 48)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 44)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(MenuBackground())
        .sheet(item: $editing) { target in
            NoteEditorSheet(noteID: target.id, autofocus: target.autofocus) { editing = nil }
                .environment(model)
        }
        .onChange(of: model.requestedBoardEdit, initial: true) { _, id in
            guard let id else { return }
            editing = EditTarget(id: id, autofocus: true)
            model.requestedBoardEdit = nil
        }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            HStack(spacing: 4) {
                ForEach(Filter.allCases) { option in
                    FilterTab(title: option.rawValue,
                              count: model.notes.filter(option.includes).count,
                              selected: filter == option) { filter = option }
                }
            }
            Spacer()
            OrderButton(
                onNewSticky: { orderNote(onScreen: true) },
                onNewInMenu: { orderNote(onScreen: false) },
                onFlavor: { flavor in orderNote(onScreen: true, flavor: flavor) }
            )
        }
    }

    private func orderNote(onScreen: Bool, flavor: Flavor? = nil) {
        let note = model.newNote(flavor: flavor, onScreen: onScreen)
        if !onScreen { model.editOnBoard(note.id) }
    }

    private func open(_ note: Note) {
        if !model.revealIfOnScreen(note.id) { editing = EditTarget(id: note.id) }
    }
}

// MARK: - Masthead & footer

struct MenuMasthead: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.menuRule).frame(width: 28, height: 1)
                Text("EST. 2026")
                    .font(Theme.serif(10, .medium))
                    .tracking(2.5)
                    .foregroundStyle(Theme.inkSoft)
                Rectangle().fill(Theme.menuRule).frame(width: 28, height: 1)
            }
            Text("chopstix")
                .font(Theme.serif(52, .semibold))
                .foregroundStyle(Theme.ink)
            Text("NOTES  ·  NOODLES  ·  NICE THINGS")
                .font(Theme.serif(11, .medium))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            VStack(spacing: 2.5) {
                Rectangle().fill(Theme.menuRule).frame(height: 1.5)
                Rectangle().fill(Theme.menuRule).frame(height: 0.75)
            }
            .padding(.top, 14)
        }
    }
}

struct MenuFooter: View {
    var body: some View {
        VStack(spacing: 8) {
            ChopsticksGlyph(color: Theme.inkFaint).frame(width: 18, height: 18)
            Text("all notes are made to order")
                .font(Theme.serif(12).italic())
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MenuBackground: View {
    var body: some View {
        Theme.menuPaper
            .overlay(
                RadialGradient(colors: [.white.opacity(0.55), .clear], center: .top, startRadius: 0, endRadius: 700)
            )
            .ignoresSafeArea()
    }
}

// MARK: - Controls

struct FilterTab: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)").foregroundStyle(Theme.inkFaint)
            }
            .font(Theme.serif(13, selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Theme.menuPaperDeep : (hovering ? Theme.menuPaperDeep.opacity(0.5) : .clear))
            )
            .overlay(Capsule().strokeBorder(selected ? Theme.menuRule : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "Order a note" — a stamp-like button, with a flavour menu beside it.
struct OrderButton: View {
    let onNewSticky: () -> Void
    let onNewInMenu: () -> Void
    let onFlavor: (Flavor) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onNewSticky) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("order a note")
                        .font(Theme.serif(14, .semibold))
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New sticky note (⌘N)")

            Rectangle().fill(Theme.menuStamp.opacity(0.35)).frame(width: 1, height: 16)

            Menu {
                Button("New Sticky Note", action: onNewSticky)
                Button("New Note in Menu", action: onNewInMenu)
                Divider()
                Section("Choose a flavour") {
                    ForEach(Flavor.allCases) { flavor in
                        Button("\(flavor.name)  \(flavor.nativeName)") { onFlavor(flavor) }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 7)
            .padding(.trailing, 11)
            .help("Choose a flavour")
        }
        .foregroundStyle(Theme.menuStamp)
        .background(Capsule().fill(Theme.menuStamp.opacity(hovering ? 0.08 : 0.03)))
        .overlay(Capsule().strokeBorder(Theme.menuStamp.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [4, 2.5])))
        .onHover { hovering = $0 }
    }
}

// MARK: - Sections

struct MenuSection: View {
    let flavor: Flavor
    let notes: [Note]
    let open: (Note) -> Void

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 20, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(flavor.accent).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(flavor.name)
                        .font(Theme.serif(21, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(flavor.nativeName)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                    DottedLeader()
                        .stroke(Theme.menuRule, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.1, 5]))
                        .frame(height: 2)
                    Text(notes.count == 1 ? "1 note" : "\(notes.count) notes")
                        .font(Theme.serif(13).italic())
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(flavor.blurb)
                    .font(Theme.serif(12.5).italic())
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 18)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(notes) { note in
                    NoteCard(note: note) { open(note) }
                }
            }
        }
    }
}

struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct EmptyMenu: View {
    let filter: BoardView.Filter
    let order: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ChopsticksGlyph(color: Theme.inkFaint).frame(width: 34, height: 34)
            Text(message)
                .font(Theme.serif(17).italic())
                .foregroundStyle(Theme.inkSoft)
            if filter == .everything {
                Button("order your first note", action: order)
                    .buttonStyle(.plain)
                    .font(Theme.serif(14, .semibold))
                    .foregroundStyle(Theme.menuStamp)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        switch filter {
        case .everything: "the kitchen is quiet"
        case .onScreen: "nothing on the screen right now"
        case .inMenu: "every note is out on the screen"
        }
    }
}
