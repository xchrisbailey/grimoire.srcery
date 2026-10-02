import Foundation

/// A timing budget, stretched on slower machines. CI's virtualized runners set
/// `GRIMOIRE_PERF_BUDGET_SCALE` so keystroke budgets fail on regressions, not on hardware.
func budget(_ duration: Duration) -> Duration {
    duration * budgetScale
}

private let budgetScale: Int = {
    let value = ProcessInfo.processInfo.environment["GRIMOIRE_PERF_BUDGET_SCALE"]
    return value.flatMap { Int($0) }.map { max($0, 1) } ?? 1
}()
