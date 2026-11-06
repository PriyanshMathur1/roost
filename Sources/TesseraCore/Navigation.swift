public enum Navigation {
    /// The index of the frame that is the best neighbour of `frames[index]` in `direction`,
    /// or nil when there is none.
    ///
    /// A candidate must lie on that side (its centre past the source's centre). Candidates
    /// that overlap the source on the cross axis win over ones that don't; then the
    /// shortest gap along the direction; then the closest centre on the cross axis.
    public static func neighbor(of index: Int, direction: Direction, frames: [Rect]) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let source = frames[index]
        var best: (index: Int, key: (Int, Double, Double))?

        for (i, candidate) in frames.enumerated() where i != index {
            let horizontal = direction == .left || direction == .right
            let ahead: Bool
            let distance: Double
            switch direction {
            case .left: ahead = candidate.midX < source.midX; distance = source.minX - candidate.maxX
            case .right: ahead = candidate.midX > source.midX; distance = candidate.minX - source.maxX
            case .up: ahead = candidate.midY < source.midY; distance = source.minY - candidate.maxY
            case .down: ahead = candidate.midY > source.midY; distance = candidate.minY - source.maxY
            }
            guard ahead else { continue }

            let overlap = horizontal
                ? min(source.maxY, candidate.maxY) - max(source.minY, candidate.minY)
                : min(source.maxX, candidate.maxX) - max(source.minX, candidate.minX)
            let crossOffset = horizontal ? abs(candidate.midY - source.midY) : abs(candidate.midX - source.midX)
            let key = (overlap > 0 ? 0 : 1, max(distance, 0), crossOffset)

            if let current = best, !(key < current.key) { continue }
            best = (i, key)
        }
        return best?.index
    }
}
