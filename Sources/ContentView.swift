import SwiftUI

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var focus: FocusCoordinator

    /// Stored rather than plain @State so the app reopens on whichever tab you
    /// were last using — otherwise long-term tasks look missing after a restart.
    @AppStorage("selectedHorizon") private var horizonRaw = Horizon.shortTerm.rawValue
    @State private var filter: Filter = .all
    @State private var editingID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var horizon: Horizon {
        get { Horizon(rawValue: horizonRaw) ?? .shortTerm }
        nonmutating set { horizonRaw = newValue.rawValue }
    }

    private var accent: Color { Paper.accent(for: horizon) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                TaskList(horizon: horizon, filter: filter, editingID: $editingID)
            }

            Hairline()
            footer
        }
        .background(Paper.sheet.ignoresSafeArea())
        .frame(minWidth: 420, minHeight: 460)
        // A shortcut aimed at the other view switches to it first; the field
        // itself claims focus once it appears.
        .onChange(of: focus.target) { target in
            switch target {
            case .bucket:   horizon = .shortTerm
            case .longTerm: horizon = .longTerm
            case nil:       break
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Todo List")
                    .font(Face.wordmark)
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text(standing)
                    .font(Face.code(10.5))
                    .foregroundStyle(Paper.muted)
            }

            horizonTabs
            filterRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 11)
        .background(Paper.band)
    }

    private var standing: String {
        if store.totalCount(in: horizon) == 0 { return "nothing here" }
        let open = store.remainingCount(in: horizon)
        return open == 0 ? "all clear" : "\(open) open"
    }

    /// The two inks. Switching them is the app's one mode change, so it gets the
    /// only underline in the interface.
    private var horizonTabs: some View {
        HStack(spacing: 20) {
            ForEach(Horizon.allCases) { candidate in
                Button {
                    withAnimation(motion(.easeInOut(duration: 0.18))) { horizon = candidate }
                } label: {
                    Text(candidate.title.lowercased())
                        .font(Face.code(11))
                        .tracking(1.5)
                        .foregroundStyle(candidate == horizon ? Paper.ink : Paper.muted)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(candidate == horizon
                                      ? Paper.accent(for: candidate) : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .help("Show \(candidate.title.lowercased()) tasks")
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paper.rule).frame(height: 1)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Filter.allCases.enumerated()), id: \.element) { index, candidate in
                if index > 0 {
                    Text("·")
                        .font(Face.code(9.5))
                        .foregroundStyle(Paper.faint)
                        .padding(.horizontal, 7)
                }
                Button {
                    withAnimation(motion(.easeInOut(duration: 0.15))) { filter = candidate }
                } label: {
                    Text(candidate.rawValue.lowercased())
                        .font(Face.code(9.5, weight: candidate == filter ? .bold : .medium))
                        .tracking(0.9)
                        .foregroundStyle(candidate == filter ? Paper.ink : Paper.faint)
                }
                .buttonStyle(.plain)
                .help("Show \(candidate.rawValue.lowercased()) tasks")
            }
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Text("\(store.totalCount(in: horizon)) tasks · \(store.doneCount(in: horizon)) done")
                .font(Face.code(10, weight: .medium))
                .foregroundStyle(Paper.muted)
                .layoutPriority(1)

            Spacer(minLength: 10)

            starToggle

            Text("·")
                .font(Face.code(10))
                .foregroundStyle(Paper.faint)
                .padding(.horizontal, 7)

            clearCompletedButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Paper.band)
    }

    /// One control with two faces: it takes the star off everything in this
    /// view, then offers to put back exactly what it removed.
    private var starToggle: some View {
        let restoring = store.unstarUndo?.horizon == horizon
        let count = restoring
            ? (store.unstarUndo?.ids.count ?? 0)
            : store.starredCount(in: horizon)
        let enabled = count > 0

        return Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) {
                if restoring { store.restoreStars() } else { store.unstarAll(in: horizon) }
            }
        } label: {
            Text(restoring ? "Restore stars" : "Unstar all")
                .font(Face.code(10, weight: .semibold))
                .foregroundStyle(!enabled ? Paper.faint : (restoring ? Paper.mark : accent))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(restoring
              ? "Put back the \(count) star\(count == 1 ? "" : "s") just removed"
              : "Take the star off every \(horizon.title.lowercased()) task")
    }

    private var clearCompletedButton: some View {
        Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) {
                store.clearCompleted(in: horizon)
            }
        } label: {
            Text("Clear completed")
                .font(Face.code(10, weight: .semibold))
                .foregroundStyle(store.doneCount(in: horizon) == 0 ? Paper.faint : accent)
        }
        .buttonStyle(.plain)
        .disabled(store.doneCount(in: horizon) == 0)
        .help("Removes finished \(horizon.title.lowercased()) tasks only")
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - The page

/// Everything between the header and the footer. Split out from ContentView so
/// it can be rendered on its own, without a scroll view, for design review.
struct TaskList: View {
    let horizon: Horizon
    let filter: Filter
    @Binding var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if horizon == .shortTerm {
                ForEach(Array(Bucket.allCases.enumerated()), id: \.element) { index, bucket in
                    BucketSection(bucket: bucket,
                                  shortcutNumber: index + 1,
                                  filter: filter,
                                  editingID: $editingID)
                }
            } else {
                LongTermList(filter: filter, editingID: $editingID)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
}

// MARK: - Shared pieces

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Paper.rule).frame(height: 1)
    }
}

/// A section's header: its four-letter code, a rule, and what is left to do.
/// The rule is not decoration — it carries the eye from the code to the count.
struct SectionRule: View {
    let code: String
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            Text(code)
                .font(Face.code(10.5))
                .tracking(1.7)
                .foregroundStyle(Paper.muted)
            Rectangle().fill(Paper.rule).frame(height: 1)
            Text("\(count)")
                .font(Face.code(10.5, weight: .medium))
                .foregroundStyle(Paper.faint)
                .monospacedDigit()
        }
        .padding(.bottom, 7)
    }
}

/// The "+ …  ⌘1" line that closes every list.
struct AddLine: View {
    let prompt: String
    let hint: String
    let accent: Color
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("+")
                .font(Face.code(12))
                .foregroundStyle(isFocused.wrappedValue ? accent : Paper.faint)
                .frame(width: 24, alignment: .leading)

            TextField(prompt, text: $draft)
                .textFieldStyle(.plain)
                .font(Face.task())
                .foregroundStyle(Paper.ink)
                .focused(isFocused)
                .onSubmit(onSubmit)

            if !isFocused.wrappedValue && draft.isEmpty {
                Text(hint)
                    .font(Face.code(9.5, weight: .medium))
                    .foregroundStyle(Paper.faint)
                    .padding(.leading, 8)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused.wrappedValue ? accent : Paper.rule)
                .frame(height: isFocused.wrappedValue ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
    }
}

struct NothingYet: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Face.code(10))
            .foregroundStyle(Paper.faint)
            .padding(.leading, 24)
            .padding(.vertical, 7)
    }
}

// MARK: - One short-term section

struct BucketSection: View {
    let bucket: Bucket
    let shortcutNumber: Int
    let filter: Filter
    @Binding var editingID: UUID?

    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var focus: FocusCoordinator
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var items: [Todo] { store.items(in: bucket, filter: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(code: bucket.code, count: store.remainingCount(in: bucket))

            if items.isEmpty {
                NothingYet(text: filter == .all
                           ? "nothing yet · ⌘\(shortcutNumber) to add"
                           : "nothing \(filter.rawValue.lowercased()) here")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { TaskRow(todo: $0, editingID: $editingID) }
                }
            }

            AddLine(prompt: bucket.prompt,
                    hint: "⌘\(shortcutNumber)",
                    accent: Paper.fresh,
                    draft: $draft,
                    isFocused: $fieldFocused,
                    onSubmit: add)
        }
        // Claimed on appear too, since switching horizon rebuilds this view
        // after the shortcut has already been set.
        .onAppear(perform: claimFocusIfWanted)
        .onChange(of: focus.target) { _ in claimFocusIfWanted() }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) { store.add(draft, to: bucket) }
        draft = ""
        fieldFocused = true          // keep going without reaching for the mouse
    }

    private func claimFocusIfWanted() {
        guard focus.target == .bucket(bucket) else { return }
        fieldFocused = true
        DispatchQueue.main.async { focus.target = nil }
    }
}

// MARK: - The long-term list (no sections)

struct LongTermList: View {
    let filter: Filter
    @Binding var editingID: UUID?

    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var focus: FocusCoordinator
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var items: [Todo] { store.longTermItems(filter: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                NothingYet(text: filter == .all
                           ? "nothing long term yet · ⌘L to add"
                           : "nothing \(filter.rawValue.lowercased()) here")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { TaskRow(todo: $0, editingID: $editingID) }
                }
            }

            AddLine(prompt: "Add a long-term task…",
                    hint: "⌘L",
                    accent: Paper.aged,
                    draft: $draft,
                    isFocused: $fieldFocused,
                    onSubmit: add)
        }
        .onAppear(perform: claimFocusIfWanted)
        .onChange(of: focus.target) { _ in claimFocusIfWanted() }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) { store.addLongTerm(draft) }
        draft = ""
        fieldFocused = true
    }

    private func claimFocusIfWanted() {
        guard focus.target == .longTerm else { return }
        fieldFocused = true
        DispatchQueue.main.async { focus.target = nil }
    }
}

// MARK: - One task

struct TaskRow: View {
    let todo: Todo
    @Binding var editingID: UUID?

    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var isHovering = false
    @FocusState private var editFocused: Bool

    private var isEditing: Bool { editingID == todo.id }
    private var accent: Color { Paper.accent(for: todo.horizon) }

    var body: some View {
        HStack(spacing: 0) {
            checkbox
                .frame(width: 24, alignment: .leading)

            HStack(spacing: 8) {
                if isEditing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Face.task())
                        .foregroundStyle(Paper.ink)
                        .focused($editFocused)
                        .onSubmit(commitEdit)
                        .onExitCommand { editingID = nil }      // Esc cancels
                        .onChange(of: editFocused) { focused in
                            // Clicking away saves rather than dropping the edit.
                            if !focused && isEditing { commitEdit() }
                        }
                } else {
                    Text(todo.title)
                        .font(Face.task(todo.isStarred ? .medium : .regular))
                        .strikethrough(todo.isDone, color: Paper.faint)
                        .foregroundStyle(todo.isDone ? Paper.faint : Paper.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2, perform: beginEdit)
                }

                star
                deleteButton
            }
            .padding(.leading, 12)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 5)
        // The margin, drawn as an overlay so its weight can never push the text
        // column sideways or stretch the row.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(todo.isStarred ? Paper.mark : Paper.rule)
                .frame(width: todo.isStarred ? 3 : 1)
                .offset(x: 24)
        }
        .background(isHovering ? Paper.hover : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(todo.isDone ? "Mark as not done" : "Mark as done") { store.toggle(todo) }
            Button(todo.isStarred ? "Remove star" : "Star") { store.toggleStar(todo) }
            Button("Edit…", action: beginEdit)
            Divider()
            Button("Delete", role: .destructive) {
                withAnimation(motion(.easeInOut(duration: 0.2))) { store.delete(todo) }
            }
        }
    }

    /// A ruled box, the way a checklist is drawn by hand — not the system circle.
    private var checkbox: some View {
        Button {
            withAnimation(motion(.easeInOut(duration: 0.18))) { store.toggle(todo) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(todo.isDone ? accent : Paper.faint, lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(todo.isDone ? accent : Color.clear)
                    )
                    .frame(width: 14, height: 14)

                if todo.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Paper.band)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(todo.isDone ? "Mark as not done" : "Mark as done")
    }

    /// Stays on show once starred, alongside the marginal mark; otherwise it
    /// fades in under the pointer.
    private var star: some View {
        Button {
            withAnimation(motion(.easeOut(duration: 0.18))) { store.toggleStar(todo) }
        } label: {
            Image(systemName: todo.isStarred ? "star.fill" : "star")
                .font(.system(size: 10))
                .foregroundStyle(todo.isStarred ? Paper.mark : Paper.faint)
        }
        .buttonStyle(.plain)
        .opacity(todo.isStarred || isHovering ? 1 : 0)
        .help(todo.isStarred ? "Remove star" : "Star this task")
    }

    private var deleteButton: some View {
        Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) { store.delete(todo) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Paper.faint)
        }
        .buttonStyle(.plain)
        .opacity(isHovering && !isEditing ? 1 : 0)
        .help("Delete task")
    }

    private func beginEdit() {
        draft = todo.title
        editingID = todo.id
        // Focus has to wait until the field actually exists in the view tree.
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        store.rename(todo, to: draft)
        editingID = nil
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}
