actor Bank { var balance = 0; func deposit(_ n: Int) -> Int { balance += n; return balance } }
@main struct Main {
    static func main() async {
        let t = Task { 42 }
        let v = await t.value
        let bank = Bank()
        let sum = await withTaskGroup(of: Int.self) { g -> Int in
            for i in 1...50 { g.addTask { _ = await bank.deposit(i); return i } }
            var s = 0; for await x in g { s += x }; return s
        }
        let d = Task.detached { await bank.balance }
        print("task", v, "group", sum, "actor", await d.value)
    }
}
