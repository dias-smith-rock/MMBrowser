import Foundation

struct DownloadItem: Codable, Equatable {
    let id: UUID
    var fileName: String
    var sourceURL: String
    var savedAt: Date

    var fileURL: URL {
        DownloadManager.directory.appendingPathComponent(fileName)
    }
}

final class DownloadManager {
    static let shared = DownloadManager()
    private let key = "mmbrowser.downloads"
    private(set) var items: [DownloadItem] = []

    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { load() }

    func download(from remote: URL, suggestedName: String?, completion: @escaping (Result<DownloadItem, Error>) -> Void) {
        let name = suggestedName?.isEmpty == false ? suggestedName! : (remote.lastPathComponent.isEmpty ? UUID().uuidString : remote.lastPathComponent)
        let dest = Self.directory.appendingPathComponent(name)
        let task = URLSession.shared.downloadTask(with: remote) { [weak self] temp, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let temp = temp else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "download", code: -1))) }
                return
            }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: temp, to: dest)
                let item = DownloadItem(id: UUID(), fileName: name, sourceURL: remote.absoluteString, savedAt: Date())
                DispatchQueue.main.async {
                    self?.items.insert(item, at: 0)
                    self?.save()
                    completion(.success(item))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        items.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
