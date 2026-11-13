import Foundation
print("bundle:", Bundle.main.executablePath ?? "nil", ProcessInfo.processInfo.processName, CommandLine.arguments.count)
