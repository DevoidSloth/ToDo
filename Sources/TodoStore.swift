import Combine
import Foundation

/// Owns the task list and keeps it on disk.
///
/// Tasks live in ~/Library/Application Support/Todo List/todos.json and are
/// rewritten atomically after every change, so a crash can't leave a half file.
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [Todo] = []

    /// What the last "unstar all" removed, so the same control can put it back.
    /// Session-only and deliberately not saved: a relaunch starts clean.
    @Published private(set) var unstarUndo: UnstarUndo?

    struct UnstarUndo: Equatable {
        let horizon: Horizon
        let ids: Set<UUID>
    }

    private let fileURL: URL

    /// Where tasks live: ~/Documents/Todo List/todos.json.
    ///
    /// Documents rather than Application Support because that folder is hidden
    /// and protected — Finder will not show it and folder pickers often refuse
    /// it outright, which made the file hard to reach from other tools.
    static var defaultStoreURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("Todo List", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    /// The pre-2026-09-02 location, kept only so existing tasks can be moved.
    static var legacyStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Todo List", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    /// Moves an older task file to the new location, once. Does nothing if the
    /// destination already exists, so it can never overwrite live tasks.
    @discardableResult
    static func migrate(from legacy: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path),
              fm.fileExists(atPath: legacy.path) else { return false }
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: legacy, to: destination)
        } catch {
            // A move can fail across volumes; a copy still gets the tasks across.
            guard (try? fm.copyItem(at: legacy, to: destination)) != nil else { return false }
        }
        // Tidy up the old folder, but only if nothing else is in it.
        let oldFolder = legacy.deletingLastPathComponent()
        if let left = try? fm.contentsOfDirectory(atPath: oldFolder.path), left.isEmpty {
            try? fm.removeItem(at: oldFolder)
        }
        return true
    }

    /// `storeURL` exists so tests can point at a scratch file; the app always
    /// uses the default location.
    init(storeURL: URL? = nil) {
        if let storeURL = storeURL {
            self.fileURL = storeURL
        } else {
            Self.migrate(from: Self.legacyStoreURL, to: Self.defaultStoreURL)
            self.fileURL = Self.defaultStoreURL
        }
        // Always, not just for the default path: without the folder every save
        // fails silently and the tasks are never written.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        load()
    }

    // MARK: - Derived values

    func remainingCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && !$0.isDone }.count
    }

    func totalCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon }.count
    }

    func doneCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && $0.isDone }.count
    }

    func starredCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && $0.isStarred }.count
    }

    /// Unfinished tasks left in one short-term section, for its header badge.
    func remainingCount(in bucket: Bucket) -> Int {
        todos.filter { $0.horizon == .shortTerm && $0.bucket == bucket && !$0.isDone }.count
    }

    /// The tasks to draw in one short-term section.
    func items(in bucket: Bucket, filter: Filter) -> [Todo] {
        todos
            .filter { $0.horizon == .shortTerm && $0.bucket == bucket && filter.matches($0) }
            .sorted(by: Self.inOrder)
    }

    /// The long-term view is one flat list, so it ignores buckets entirely.
    func longTermItems(filter: Filter) -> [Todo] {
        todos
            .filter { $0.horizon == .longTerm && filter.matches($0) }
            .sorted(by: Self.inOrder)
    }

    /// Alphabetical, with finished tasks moved to the bottom. Stars do not
    /// affect the order.
    ///
    /// The comparison is `localizedStandardCompare` — the same one Finder uses —
    /// so case is ignored and embedded numbers sort as numbers ("13.2" before
    /// "13.10", not after).
    private static func inOrder(_ a: Todo, _ b: Todo) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    // MARK: - Mutations

    func add(_ rawTitle: String, to bucket: Bucket) {
        append(rawTitle, bucket: bucket, horizon: .shortTerm)
    }

    /// Long-term tasks have no section; the bucket is a placeholder they never show.
    func addLongTerm(_ rawTitle: String) {
        append(rawTitle, bucket: .other, horizon: .longTerm)
    }

    private func append(_ rawTitle: String, bucket: Bucket, horizon: Horizon) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        todos.append(Todo(title: title, bucket: bucket, horizon: horizon))
        save()
    }

    func toggle(_ todo: Todo) {
        update(todo) { $0.isDone.toggle() }
    }

    func toggleStar(_ todo: Todo) {
        // Once a star is set by hand, "restore" would fight the user.
        unstarUndo = nil
        update(todo) { $0.isStarred.toggle() }
    }

    func rename(_ todo: Todo, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty rename means "delete", matching how most task apps behave.
        if title.isEmpty {
            delete(todo)
        } else {
            update(todo) { $0.title = title }
        }
    }

    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        save()
    }

    /// Takes the star off every task in one horizon, remembering which ones so
    /// `restoreStars` can undo it. Scoped like clearCompleted: the view you are
    /// not looking at is never touched.
    func unstarAll(in horizon: Horizon) {
        let ids = Set(todos.filter { $0.horizon == horizon && $0.isStarred }.map(\.id))
        guard !ids.isEmpty else { return }
        for i in todos.indices where ids.contains(todos[i].id) {
            todos[i].isStarred = false
        }
        unstarUndo = UnstarUndo(horizon: horizon, ids: ids)
        save()
    }

    /// Puts back exactly the stars the last `unstarAll` removed. Tasks deleted
    /// in the meantime are simply skipped.
    func restoreStars() {
        guard let undo = unstarUndo else { return }
        for i in todos.indices where undo.ids.contains(todos[i].id) {
            todos[i].isStarred = true
        }
        unstarUndo = nil
        save()
    }

    /// Scoped to the horizon on screen, so clearing one view never touches the other.
    func clearCompleted(in horizon: Horizon) {
        todos.removeAll { $0.horizon == horizon && $0.isDone }
        save()
    }

    private func update(_ todo: Todo, _ change: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        change(&todos[i])
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        todos = (try? decoder.decode([Todo].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(todos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
