import SwiftCompilerPlugin
import SwiftSyntaxMacros
import SwiftMacros
import ObservationMacros
import FoundationMacros
import TestingMacros

struct BuiltinMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] {
        SwiftMacros.providedMacros + ObservationMacros.providedMacros + FoundationMacros.providedMacros + TestingMacros.providedMacros
    }
}

try BuiltinMacros.main()
