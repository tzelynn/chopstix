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
                                MenuSection(flavor: flavor, notes: notes, open: open) {
                                    // Keep the new note visible under the current filter.
                                    orderNote(onScreen: filter == .onScreen, flavor: flavor)
                                }
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
                onNewMarkdown: { model.newMarkdownNote(onScreen: true) },
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
    let onNewMarkdown: () -> Void
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
                Button("New Markdown Note", action: onNewMarkdown)
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
    let add: () -> Void
    @Environment(AppModel.self) private var model
    @State private var hovering = false

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
                    AddToSectionButton(flavor: flavor, action: add)
                }
                if model.sectionDescription(for: flavor) == nil {
                    // No description yet: its hover hint shares the blurb's line rather than adding one.
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        SectionDescription(flavor: flavor, sectionHovered: hovering)
                        SectionBlurb(flavor: flavor).fixedSize()
                    }
                    .padding(.leading, 18)
                } else {
                    SectionBlurb(flavor: flavor)
                    SectionDescription(flavor: flavor, sectionHovered: hovering)
                        .padding(.leading, 18)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(notes) { note in
                    NoteCard(note: note) { open(note) }
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

/// A small stamp beside a section's note count that orders a note of that flavour.
struct AddToSectionButton: View {
    let flavor: Flavor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("add")
                    .font(Theme.serif(12, .semibold))
            }
            .foregroundStyle(Theme.menuStamp)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.menuStamp.opacity(hovering ? 0.08 : 0.03)))
            .overlay(Capsule().strokeBorder(Theme.menuStamp.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, dash: [3, 2])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add a \(flavor.name) note")
    }
}

/// A section's menu description, right-aligned under the header. Click to rewrite it.
struct SectionBlurb: View {
    let flavor: Flavor
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var isCustom: Bool { model.blurb(for: flavor) != flavor.blurb }

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft, prompt: Text(flavor.blurb))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .opacity(hovering ? 1 : 0)
                    Text(model.blurb(for: flavor))
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditing)
                .onHover { hovering = $0 }
                .help("Click to rewrite this description")
                .contextMenu {
                    Button("Edit Description", action: beginEditing)
                    Button("Restore Original Description") { model.setBlurb(flavor, nil) }
                        .disabled(!isCustom)
                }
            }
        }
        .font(Theme.serif(12.5).italic())
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func beginEditing() {
        draft = model.blurb(for: flavor)
        editing = true
    }

    private func commit() {
        guard editing else { return }
        model.setBlurb(flavor, draft)
        editing = false
    }
}

/// The user's own note about what a section is for, under its header. Click to write or edit it;
/// while empty, an "add a description" hint appears only when the section is hovered.
struct SectionDescription: View {
    let flavor: Flavor
    let sectionHovered: Bool
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var text: String? { model.sectionDescription(for: flavor) }

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft, prompt: Text("what's this section for?"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .foregroundStyle(Theme.inkSoft)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .onAppear { DispatchQueue.main.async { focused = true } }
                    .modifier(DescriptionField(highlighted: true, dashed: false))
            } else if let text {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(text)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                        .opacity(hovering ? 1 : 0)
                }
                .modifier(DescriptionField(highlighted: hovering, dashed: false))
                .onTapGesture(perform: beginEditing)
                .onHover { hovering = $0 }
                .help("Click to edit this description")
                .contextMenu {
                    Button("Edit Section Description", action: beginEditing)
                    Button("Remove Section Description") { model.setSectionDescription(flavor, nil) }
                }
            } else {
                // The whole free stretch of the line is the target, outlined on hover so it reads as a field.
                Button(action: beginEditing) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        Text("add a description")
                    }
                    .foregroundStyle(hovering ? Theme.inkSoft : Theme.inkFaint)
                    .modifier(DescriptionField(highlighted: hovering, dashed: true))
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .opacity(sectionHovered || hovering ? 1 : 0)
                .help("Describe what this section is for")
            }
        }
        .font(Theme.serif(13.5))
        // Pull the padded box back so its text stays aligned with the header above.
        .padding(.leading, -DescriptionField.inset)
    }

    private func beginEditing() {
        draft = text ?? ""
        editing = true
    }

    private func commit() {
        guard editing else { return }
        model.setSectionDescription(flavor, draft)
        editing = false
    }
}

/// The padded, full-width box a section description sits in, so the whole line is clickable.
/// Tinted (and outlined, when `dashed`) while highlighted.
private struct DescriptionField: ViewModifier {
    static let inset: CGFloat = 8
    let highlighted: Bool
    let dashed: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        content
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(shape.fill(Theme.ink.opacity(highlighted ? 0.045 : 0)))
            .overlay(shape.strokeBorder(Theme.inkFaint.opacity(highlighted && dashed ? 0.7 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(shape)
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
