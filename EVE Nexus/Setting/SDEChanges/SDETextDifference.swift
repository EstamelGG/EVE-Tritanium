import Foundation

/// Compare grapheme clusters so CJK text and emoji remain intact. Preserve raw SDE text.
struct SDETextDifference {
    struct Segment: Equatable {
        var text: String
        let changed: Bool
    }

    let old: [Segment]
    let new: [Segment]

    init(old: String, new: String) {
        let before = Array(old), after = Array(new)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1]
        {
            suffix += 1
        }
        let oldMiddle = Array(before[prefix ..< (before.count - suffix)])
        let newMiddle = Array(after[prefix ..< (after.count - suffix)])
        var deleted = Set<Int>(), inserted = Set<Int>()
        // Bound the worst case for very large, unrelated descriptions.
        if oldMiddle.count + newMiddle.count <= 2000 {
            for change in newMiddle.difference(from: oldMiddle) {
                switch change {
                case let .remove(offset, _, _): deleted.insert(prefix + offset)
                case let .insert(offset, _, _): inserted.insert(prefix + offset)
                }
            }
        } else {
            deleted.formUnion(prefix ..< (before.count - suffix))
            inserted.formUnion(prefix ..< (after.count - suffix))
        }
        self.old = Self.segments(before, changed: deleted)
        self.new = Self.segments(after, changed: inserted)
    }

    private static func segments(_ characters: [Character], changed: Set<Int>) -> [Segment] {
        var result: [Segment] = []
        for (index, character) in characters.enumerated() {
            let isChanged = changed.contains(index)
            if result.last?.changed == isChanged {
                result[result.count - 1].text.append(character)
            } else {
                result.append(Segment(text: String(character), changed: isChanged))
            }
        }
        return result
    }

    /// Collapse unchanged context, while keeping every changed fragment visible.
    static func compact(_ segments: [Segment]) -> [Segment] {
        guard segments.contains(where: \.changed) else { return segments }
        return segments.enumerated().map { index, segment in
            guard !segment.changed, segment.text.count > 160 else { return segment }
            let text: String
            if index == 0 {
                text = "…" + segment.text.suffix(80)
            } else if index == segments.count - 1 {
                text = segment.text.prefix(80) + "…"
            } else {
                text = segment.text.prefix(80) + " … " + segment.text.suffix(80)
            }
            return Segment(text: text, changed: false)
        }
    }
}
