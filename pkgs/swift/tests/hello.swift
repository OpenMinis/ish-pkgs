import Foundation

struct Greeting: Codable {
    let message: String
    let year: Int
    let tags: [String]
}

print("Hello from Swift on musl! 🎉")
let now = Date()
let fmt = ISO8601DateFormatter()
print("Now:", fmt.string(from: now))
let year = Calendar(identifier: .gregorian).component(.year, from: now)
let g = Greeting(message: "hi", year: year, tags: ["alpine", "musl", "static"])
let enc = JSONEncoder()
enc.outputFormatting = [.sortedKeys]
let data = try enc.encode(g)
print(String(data: data, encoding: .utf8)!)
let back = try JSONDecoder().decode(Greeting.self, from: data)
print("Decoded:", back.message, back.year, back.tags.count)
let arr = (1...10).map { $0 * $0 }.filter { $0 % 2 == 0 }
print(arr.reduce(0, +))
