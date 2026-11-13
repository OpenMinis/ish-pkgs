# swift

The Swift 6.4.2 compiler and package manager for iSH (Alpine Linux / musl, arm64), built from the upstream
`swift-6.4.2-RELEASE` sources as a fully statically linked toolchain.

Every tool (`swift-frontend`, `swift-driver`, SwiftPM, `clang`, `lld`) is a static `aarch64-swift-linux-musl`
executable, so the package depends on nothing but `/bin/sh`. Programs it builds are static executables as well.

## Install

```sh
apk add swift          # ~150 KB launcher; pulls in zstd, tar, curl
swiftc -version        # first run downloads the toolchain (~173 MB) once
```

The `swift` apk does **not** contain the toolchain. The toolchain is ~173 MB compressed (708 MB unpacked),
which is above GitHub's 100 MB per-file limit for the apk repository, so the apk ships a small launcher:

- `/usr/local/bin/{swift,swiftc,swift-build,swift-package,swift-run,swift-test,swiftc-info}` are symlinks to
  `/usr/local/share/swift/bin/swift-launcher`.
- On the first invocation the launcher downloads `swift-ish-arm64-v6.4.2.tar.zst` from this repository's
  GitHub Release `v6.4.2`, checks its SHA-256 (pinned in the launcher), and unpacks it into `/usr/local/swift`.
  It then runs the real command. Later invocations `exec` straight into `/usr/local/swift/bin/<cmd>`.
- `swiftc --status` shows whether the toolchain is installed; `swiftc --install-payload` re-downloads it;
  `swiftc --uninstall-payload` removes `/usr/local/swift`.
- `SWIFT_DOWNLOAD_URL=<url>` overrides the download location (e.g. a mirror). The SHA-256 check still applies.
- `apk del swift` removes the launcher only; delete `/usr/local/swift` yourself (or run
  `swiftc --uninstall-payload` before removing the package).

You can also unpack the release archive anywhere by hand (`zstd -dc swift-ish-arm64-v6.4.2.tar.zst | tar -x -C <dir>`)
and put `<dir>/bin` on `PATH`; the tree is relocatable. Keep it out of `/usr`: `bin/` contains `clang`,
`clang++`, `ld.lld`, `lld`, `llvm-ar` and the tree contains a musl/libc++ sysroot (`include/`, `lib/*.a`), which
would collide with Alpine's `clang`, `lld`, `musl-dev` and `libc++-dev`.

## Use

```sh
cat > hello.swift <<'EOF'
import Foundation
struct Greeting: Codable { let msg: String; let year: Int }
let year = Calendar(identifier: .gregorian).component(.year, from: Date())
print(String(data: try JSONEncoder().encode(Greeting(msg: "hi", year: year)), encoding: .utf8)!)
EOF

swiftc hello.swift -o hello && ./hello
swiftc -O hello.swift -o hello          # optimised
swiftc -g hello.swift -o hello          # with debug info (not stripped)
swift hello.swift arg1 arg2             # compile to a cached binary, then run it
swiftc-info                             # show the toolchain configuration
```

`swift file.swift` is a convenience, **not an interpreter**: the file is compiled to
`${TMPDIR:-/tmp}/swift-script-cache-<uid>/` and the binary is reused until the source or the options change.

### Macros and swift-testing

The built-in macros work out of the box: `@Observable`, `#Predicate` / `#Expression`, `@TaskLocal`,
`@DebugDescription`, `@Test` / `@Suite` / `#expect` / `#require`.

A single-file test program needs an entry point and `-parse-as-library`:

```swift
import Testing
@Test func add() { #expect(1 + 1 == 2) }
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
```

### SwiftPM

```sh
mkdir demo && cd demo && swift package init --type executable
swift build                 # or: swift build -c release
swift run
swift test                  # swift-testing only
```

Remote dependencies need `git` (`apk add git`).

### Options (environment variables read by the `swiftc` wrapper)

| Variable | Effect |
|---|---|
| `SWIFTC_DRIVER=new` | use swift-driver instead of the default legacy C++ driver |
| `SWIFTC_KEEP_SYMBOLS=1` | do not add `--gc-sections -s` when linking (never added when `-g` is given) |
| `SWIFTC_ICU=full\|small\|tiny` | ICU data linked into programs that use Foundation's locale features (default `full`) |
| `SWIFTC_STACK_SIZE=<bytes>` | default stack size of non-main threads in linked programs (default 8388608; `0` keeps musl's 128 KB) |
| `SWIFT_SCRIPT_CACHE=<dir>` | cache directory for `swift file.swift` |

`bin/swiftc` is a small shell script; it runs the real driver with
`-sdk <prefix> -resource-dir <prefix>/lib/swift_static -static-executable -use-ld=lld
-load-plugin-executable <built-in macros>` and, when linking, `--gc-sections -s` and `-z stack-size=8388608`.

### Executable size (`-O`)

| Program | default | `SWIFTC_ICU=small` | `SWIFTC_ICU=tiny` |
|---|---|---|---|
| `import Foundation`, Date/Calendar/JSON | 54 MB | 28.5 MB | 25 MB |
| same with `import FoundationEssentials` | 9.6 MB | – | – |
| standard library only | 5.8 MB | – | – |

The default (`full`) is the official behaviour: all ~800 locales and every converter. **If size matters, use
`SWIFTC_ICU=small`**: it keeps root + English + Chinese (Simplified and Traditional) locale data, Chinese
collation, transliteration and the GB18030 / GBK / Big5 converters. Formatting for any other locale falls back
to English patterns (no crash), other legacy encodings return nil. `tiny` keeps only root + English (Chinese
locales fall back too, no transliteration, no legacy encodings). Programs that need no locale support at all are
smallest with `import FoundationEssentials` instead of `import Foundation`.

## Known limitations

- Output is always a **static executable or a static library**. No shared libraries (`-emit-library` without
  `-static`), no `dlopen`.
- No REPL, no interpreter, no LLDB, no sourcekit-lsp, no XCTest (`swift test` runs swift-testing only).
- Only the toolchain's built-in macros are provided prebuilt. A package that defines its own macros has to build
  swift-syntax on the device; that is untested and will be slow.
- SwiftPM uses its "native" build system (the newer Swift Build backend cannot run in a static executable).
  Build-tool plugins are untested.
- Code generation for aarch64 only.
- Programs are linked with an 8 MB default stack for non-main threads (musl's own default of 128 KB is too small
  for recursive code inside Swift tasks). This is address-space reservation only. `SWIFTC_STACK_SIZE=0` restores
  musl's default.
- `TimeZone(identifier:)` needs the system time zone database (`apk add tzdata`).
- Memory: compiling a file that imports Foundation peaks at roughly 300–400 MB, linking at about 300 MB.

## Differences from the official binaries

Upstream publishes no musl-hosted compiler; the tools here are the upstream sources built for a new host.
The target runtime is the official Static Linux SDK with **five archive members replaced** (plus libraries the
SDK does not contain). In a normal Linux environment the replaced objects behave like the originals: the new code
paths are only reached where the original aborted. Background: [ISH-NOTES.md](ISH-NOTES.md).

| Archive (`lib/swift_static/linux-static/`) | Member | Change | Why |
|---|---|---|---|
| `libswiftCore.a` | `Paths.cpp.o` | runtime path lookup retries `/proc/self/exe`, then uses `AT_EXECFN` / `argv[0]`; never fatal | iSH: the readlink fails intermittently; concurrency programs aborted |
| `libswiftCore.a` | `CommandLine.cpp.o` | `CommandLine.arguments` works without `/proc/self/maps` | arguments were empty when the file is unreadable |
| `libdispatch.a` | `lock.c.o` | unfair lock falls back to a yielding spin lock when PI futexes are unsupported | iSH: silent SIGTRAP under lock contention |
| `libdispatch.a` | `workqueue.c.o` | unreadable `/proc/<tid>/stat` is skipped | was a silent SIGTRAP |
| `libCoreFoundation.a` | `CFPlatform.c.o` | process path falls back to `AT_EXECFN` | `Bundle.main` trapped without `/proc/self/exe` |

Added: swift-testing static libraries (`libTesting.a` …), reduced ICU data objects (`lib/swift_static/icu-data/`),
SwiftPM's manifest runtime as static libraries (`lib/swift/pm/`), the built-in macro plugin
(`bin/swift-builtin-macros`), the wrapper scripts. Removed: DWARF debug info from all archives, x86_64 modules.
The host tools contain the same patched runtime, plus small fixes in LLVM, swift-driver and SwiftPM
(see `patches/`). `PROVENANCE.txt` in the zip lists every patch and the SHA-256 of every file.

## Files

```
bin/                 scripts: swift, swiftc, swiftc-info
                     swift-frontend (+ links swift-autolink-extract, swiftc-legacy-driver, swift-legacy-driver)
                     swift-driver
                     swift-package-manager (+ links swift-build, swift-package, swift-run, swift-test, swift-sdk)
                     swift-builtin-macros
                     clang-21 (+ links clang, clang++), lld (+ link ld.lld), llvm-ar
                     aarch64-swift-linux-musl-clang.cfg, aarch64-swift-linux-musl-clang++.cfg
include/             musl and libc++ headers (sysroot)
lib/*.a, lib/*.o     musl libc, libc++, libunwind, crt objects and the other static libraries of the SDK (sysroot)
lib/swift/           compiler resource directory: clang headers and compiler-rt (clang/), shims/,
                     SwiftPM manifest runtime (pm/), toolbin/ar -> llvm-ar, links into swift_static/
lib/swift_static/    static Swift runtime for aarch64-swift-linux-musl, swift-testing, icu-data/
lib/clang/21         -> ../swift/clang
share/swift/         diagnostics data, BUILD_INFO
SDKSettings.json
PROVENANCE.txt
```

A possible split into packages (every file belongs to exactly one line):

| Package | Files |
|---|---|
| frontend | `bin/swift-frontend`, `bin/swift-autolink-extract`, `bin/swiftc-legacy-driver`, `bin/swift-legacy-driver`, `bin/swiftc`, `bin/swift`, `bin/swiftc-info`, `share/swift/` |
| driver (optional, `SWIFTC_DRIVER=new`) | `bin/swift-driver` |
| SwiftPM | `bin/swift-package-manager`, `bin/swift-build`, `bin/swift-package`, `bin/swift-run`, `bin/swift-test`, `bin/swift-sdk`, `lib/swift/pm/` |
| clang | `bin/clang-21`, `bin/clang`, `bin/clang++`, `bin/lld`, `bin/ld.lld`, `bin/llvm-ar`, `bin/*.cfg`, `lib/swift/clang/`, `lib/clang/`, `lib/swift/toolbin/` |
| runtime | `lib/swift_static/`, the rest of `lib/swift/` (`shims/` and the links) |
| sysroot | `include/`, `lib/*.a`, `lib/*.o`, `lib/libc++.modules.json`, `SDKSettings.json` |
| macros | `bin/swift-builtin-macros` |

`swiftc` needs frontend + clang + runtime + sysroot to produce an executable; macros is needed as soon as a
source file uses a macro (the wrapper always passes the plugin path; a missing plugin only matters when a macro is
expanded). SwiftPM additionally needs nothing but those. `bin/swift` works without SwiftPM for the
`swift file.swift` mode and prints a clear message for `swift build` when SwiftPM is absent.

## Building

```sh
./build.sh swift-6.4.2-RELEASE [outdir]        # -> outdir/swift-ish-arm64-v6.4.2.zip + SHA256SUMS
./build.sh swift-6.4.2-RELEASE --list          # show stage state
./build.sh swift-6.4.2-RELEASE --from swiftpm  # redo a stage and everything after it
./build.sh swift-6.4.2-RELEASE --only selftest --hostile
```

Requirements: an **arm64** host with Docker (Linux, or macOS with Docker Desktop / OrbStack), about 40 GB of free
disk in `$WORK` (default `./work`) plus ~7 GB for the image, 12 GB of RAM for containers, 2–3 hours on 8–12 cores.
The build is not a cross build across architectures: freshly built aarch64 tools are executed during the build.

| Stage | What it does |
|---|---|
| `image` | build image: `swift:<version>` + the official Static Linux SDK + cmake/ninja |
| `checkout` | clone swiftlang/swift at the tag, `update-checkout` all sibling repositories to the same tag |
| `deps` | static libuuid / SQLite / ncurses for musl, taken from Alpine packages |
| `patch` | `git apply` every `patches/<repo>/*.patch` inside `src/<repo>`, in file-name order |
| `native` | upstream `build-script`: native LLVM (tblgen), cmark, and the cross LLVM build directory; stopped there |
| `llvm` | reconfigure and build the musl-host LLVM / clang / lld |
| `runtime` | rebuild the five patched runtime objects and replace them in the SDK archives |
| `swift` | musl-host `swift-frontend` (direct CMake, bootstrapped with the image's compiler) |
| `driver` | swift-driver |
| `macros` | the built-in macro plugin executable |
| `testing` | swift-testing static libraries |
| `swiftpm` | SwiftPM manifest runtime (static) and the `swift-package-manager` multi-call binary |
| `icu` | reduced ICU data objects |
| `assemble` | lay out the toolchain, strip, add wrappers |
| `selftest` | in `alpine:3.21`: version, hello (Foundation), macros, swift-testing, concurrency, deep recursion in tasks, SwiftPM build/test; every product 20 runs |
| `package` | `PROVENANCE.txt`, zip, `SHA256SUMS` |

Patches live in one directory per repository (`patches/swift/`, `patches/llvm-project/`, …) and are applied
inside that repository. Each patch starts with a note on what it changes, why, and whether upstream might take it.

`update.sh` checks (read-only) whether upstream has a newer release tag. For a new version add the Static Linux SDK
checksum to `docker/static-sdk-checksums`, run `build.sh` with the new tag and refresh the patches that no longer
apply.

The pitfalls met while getting here are in [NOTES.md](NOTES.md).

### Releasing

The toolchain is published as a GitHub Release asset, and the apk only carries the launcher:

```sh
# 1. zip -> tar.zst (keeps symlinks and modes)
mkdir x && unzip -q dist/swift-ish-arm64-v6.4.2.zip -d x
tar -C x -cf - . | zstd -19 -T0 -o swift-ish-arm64-v6.4.2.tar.zst
sha256sum swift-ish-arm64-v6.4.2.tar.zst

# 2. upload it to a Release named after the tag
gh release create v6.4.2 -R OpenMinis/ish-pkgs swift-ish-arm64-v6.4.2.tar.zst

# 3. pin version + SHA-256 in files/swift-launcher (SWIFT_VERSION, EXPECTED_SHA256), then
tools/publish.sh pkgs/swift/dist/swift-ish-arm64-v6.4.2.zip v6.4.2   # launcher apk + signed index
```

The launcher refuses an archive whose SHA-256 differs from the pinned value, so a new archive always needs a new
launcher (bump the apk revision).

## License

Swift is licensed under Apache-2.0 WITH LLVM-exception (the Swift Runtime Library Exception); LLVM, clang, lld,
libc++, libunwind and compiler-rt under Apache-2.0 WITH LLVM-exception; swift-syntax, swift-driver, SwiftPM,
swift-testing, Foundation and libdispatch under Apache-2.0 (most with the runtime library exception); ICU under
the Unicode license; musl under MIT. `LICENSE.upstream` contains Swift's license text and a notice listing the
bundled components. The files in this directory (build scripts, patches, wrappers) are provided under the same
terms as the components they modify.
