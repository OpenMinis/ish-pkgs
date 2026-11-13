import Dispatch
actor Counter { var n = 0; func inc() -> Int { n += 1; return n } }
func work(_ i: Int) async -> Int { try? await Task.sleep(nanoseconds: 1_000_000); return i * 2 }
@main struct Main {
    static func main() async {
        let c = Counter()
        let total = await withTaskGroup(of: Int.self) { g -> Int in
            for i in 1...20 { g.addTask { _ = await c.inc(); return await work(i) } }
            var s = 0; for await v in g { s += v }; return s
        }
        print("total", total, "count", await c.n)
        let r = try! Regex("[a-z]+[0-9]+")
        print("regex:", "abc123 xyz".firstMatch(of: r)!.0)
        let q = DispatchQueue(label: "q"); q.sync { print("dispatch ok") }
    }
}
