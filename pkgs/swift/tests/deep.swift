// deep recursion inside concurrent tasks: needs more than musl's 128 KB thread stacks
func depth(_ n: Int) -> Int { n == 0 ? 0 : 1 + depth(n - 1) }
@main struct Main {
  static func main() async {
    let total = await withTaskGroup(of: Int.self) { g in
      for _ in 0..<200 { g.addTask { depth(20000) } }
      var s = 0; for await v in g { s += v }; return s
    }
    print("deep ok", total)
  }
}
