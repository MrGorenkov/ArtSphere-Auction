import Foundation

/// Persists the user-chosen ordering of paintings on showroom walls, keyed by collection ID.
/// Layouts are stored in UserDefaults as a `[collectionId: [artworkId]]` JSON map.
enum ShowroomLayoutStore {
    private static let key = "showroom_layout_v1"

    private static var allLayouts: [String: [String]] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    /// Returns artworks reordered according to the stored layout for the given collection.
    /// IDs not in the saved layout keep their original relative order at the end.
    static func ordered(_ artworks: [NFTArtwork], collectionId: UUID?) -> [NFTArtwork] {
        guard let collectionId,
              let order = allLayouts[collectionId.uuidString] else { return artworks }
        let orderedIds = order.compactMap { UUID(uuidString: $0) }
        let indexMap = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($1, $0) })
        return artworks.sorted { lhs, rhs in
            switch (indexMap[lhs.id], indexMap[rhs.id]) {
            case let (l?, r?):    return l < r
            case (_?, nil):        return true
            case (nil, _?):        return false
            case (nil, nil):       return false
            }
        }
    }

    /// Persists the current layout (an ordered list of painting UUIDs) for the collection.
    static func save(order: [UUID], collectionId: UUID?) {
        guard let collectionId else { return }
        var layouts = allLayouts
        layouts[collectionId.uuidString] = order.map(\.uuidString)
        allLayouts = layouts
    }

    /// Removes the saved layout for the given collection.
    static func reset(collectionId: UUID?) {
        guard let collectionId else { return }
        var layouts = allLayouts
        layouts.removeValue(forKey: collectionId.uuidString)
        allLayouts = layouts
    }
}
