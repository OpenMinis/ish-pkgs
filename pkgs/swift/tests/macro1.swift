import Foundation
import Observation

@Observable final class M { var x = 0; var name = "a" }

enum Ctx { @TaskLocal static var id: Int = 7 }

@DebugDescription
struct P: CustomDebugStringConvertible { var a = 1; var debugDescription: String { "P(\(a))" } }

struct Opts: OptionSet { let rawValue: Int; static let a = Opts(rawValue: 1) }

@main struct Main {
  static func main() async throws {
    let m = M()
    nonisolated(unsafe) var changed = false
    withObservationTracking { _ = m.x } onChange: { changed = true }
    m.x = 5
    print("observable:", m.x, changed)
    let p = #Predicate<Int> { $0 > 3 }
    print("predicate:", try p.evaluate(5), try p.evaluate(1))
    let e = #Expression<Int, Int> { $0 * 2 + 1 }
    print("expression:", try e.evaluate(20))
    Ctx.$id.withValue(42) { print("tasklocal:", Ctx.id) }
    print("default:", Ctx.id, P())
  }
}
