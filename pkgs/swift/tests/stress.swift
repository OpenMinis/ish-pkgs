import Dispatch
actor Acc { var v = 0; func add(_ n: Int) { v += n } }
@main struct Main {
    static func main() async {
        let acc = Acc()
        for round in 0..<20 {
            await withTaskGroup(of: Void.self) { g in
                for i in 0..<200 { g.addTask { await acc.add(i); if i % 50 == 0 { try? await Task.sleep(nanoseconds: 200_000) } } }
            }
            _ = round
        }
        let q = DispatchQueue(label: "c", attributes: .concurrent); let grp = DispatchGroup(); let lock = DispatchQueue(label: "l")
        var n = 0
        for _ in 0..<2000 { q.async(group: grp) { lock.sync { n += 1 } } }
        grp.wait()
        print("stress ok", await acc.v, n)
    }
}
