import Testing
import Foundation

@Test func addition() { #expect(1 + 1 == 2) }
@Test func failing() { withKnownIssue { #expect(1 + 1 == 3) } }
@Test(arguments: [1, 2, 3]) func param(_ n: Int) throws { let v = try #require(Optional(n)); #expect(v > 0) }
@Suite struct S { @Test func date() async { #expect(Date().timeIntervalSince1970 > 0) } }

@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
