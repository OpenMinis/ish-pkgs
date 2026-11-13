#!/bin/sh
# One statically linked compiler-plugin executable providing the toolchain's
# built-in macros (SwiftMacros, ObservationMacros, FoundationMacros, TestingMacros).
# A static compiler cannot dlopen() lib*Macros.so, but it can run an executable
# plugin (-load-plugin-executable <path>#<module>,...).
. "$PKG/stages/common.sh"
"$PKG/stages/patch-sdk.sh" check
P=$W/macros-plugin
rm -rf "$P"; mkdir -p "$P"; cp -R "$PKG/files/macros-plugin/." "$P/"
for m in SwiftMacros ObservationMacros FoundationMacros; do mkdir -p "$P/Sources/$m"; done
cp "$W"/src/swift/lib/Macros/Sources/SwiftMacros/*.swift "$P/Sources/SwiftMacros/"
cp "$W"/src/swift/lib/Macros/Sources/ObservationMacros/*.swift "$P/Sources/ObservationMacros/"
cp "$W"/src/swift-foundation/Sources/FoundationMacros/*.swift "$P/Sources/FoundationMacros/"
# -L: the directory contains a symlink into _TestDiscovery
cp -RL "$W/src/swift-testing/Sources/TestingMacros" "$P/Sources/TestingMacros"
rm -f "$P/Sources/TestingMacros/CMakeLists.txt" "$P/Sources/TestingMacros/TestingMacrosMain.swift"
cat > "$P/Sources/SwiftMacros/_Provided.swift" <<'S'
import SwiftSyntaxMacros
public let providedMacros: [Macro.Type] = [
    OptionSetMacro.self, DebugDescriptionMacro.self, _DebugDescriptionPropertyMacro.self,
    TaskLocalMacro.self, DistributedResolvableMacro.self,
    SwiftifyImportMacro.self, SwiftifyImportProtocolMacro.self,
]
S
cat > "$P/Sources/ObservationMacros/_Provided.swift" <<'S'
import SwiftSyntaxMacros
public let providedMacros: [Macro.Type] = [
    ObservableMacro.self, ObservationTrackedMacro.self, ObservationIgnoredMacro.self,
]
S
cat > "$P/Sources/FoundationMacros/_Provided.swift" <<'S'
import SwiftSyntaxMacros
public let providedMacros: [Macro.Type] = [
    PredicateMacro.self, ExpressionMacro.self, BundleMacro.self,
]
S
cat > "$P/Sources/TestingMacros/_Provided.swift" <<'S'
public import SwiftSyntaxMacros
public let providedMacros: [any Macro.Type] = [
    SuiteDeclarationMacro.self, TestDeclarationMacro.self, ExpectMacro.self, RequireMacro.self,
    AmbiguousRequireMacro.self, NonOptionalRequireMacro.self, ExpectThrowsMacro.self,
    RequireThrowsMacro.self, RequireThrowsNeverMacro.self, ExitTestExpectMacro.self,
    ExitTestRequireMacro.self, ExitTestCapturedValueMacro.self, ExitTestBadCapturedValueMacro.self,
    ExitTestIncorrectlyCapturedValueMacro.self, TagMacro.self, SourceLocationMacro.self, PragmaMacro.self,
]
S
cd "$P"
rm -f "$B/macros-plugin-static/out/Products/$PRODUCTS/swift-builtin-macros"
run macros swift build -c release --swift-sdk $TRIPLE --product swift-builtin-macros --scratch-path "$B/macros-plugin-static"
[ -x "$B/macros-plugin-static/out/Products/$PRODUCTS/swift-builtin-macros" ]
