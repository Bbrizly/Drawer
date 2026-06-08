struct PanelTransitionState {
    private(set) var isShown = false
    private var generation = 0

    @discardableResult
    mutating func beginShow() -> Int {
        generation += 1
        isShown = true
        return generation
    }

    mutating func beginHide() -> Int {
        generation += 1
        isShown = false
        return generation
    }

    func shouldOrderOut(hideGeneration: Int) -> Bool {
        hideGeneration == generation && !isShown
    }
}
