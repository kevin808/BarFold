import Foundation

struct PlacementDiscoveryTracker {
    private var observedPIDsByID: [String: pid_t] = [:]
    private var missingScanCountsByID: [String: Int] = [:]

    mutating func changedIDs(in currentPIDsByID: [String: pid_t]) -> Set<String> {
        var changed: Set<String> = []
        for (id, pid) in currentPIDsByID {
            if observedPIDsByID[id] != pid {
                changed.insert(id)
            }
            observedPIDsByID[id] = pid
            missingScanCountsByID.removeValue(forKey: id)
        }

        for id in Array(observedPIDsByID.keys) where currentPIDsByID[id] == nil {
            let missingCount = missingScanCountsByID[id, default: 0] + 1
            if missingCount >= 2 {
                observedPIDsByID.removeValue(forKey: id)
                missingScanCountsByID.removeValue(forKey: id)
            } else {
                missingScanCountsByID[id] = missingCount
            }
        }
        return changed
    }

    mutating func reset() {
        observedPIDsByID.removeAll()
        missingScanCountsByID.removeAll()
    }
}
