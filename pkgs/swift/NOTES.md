# Build notes: pitfalls and how they were solved

Maintainer notes for `build.sh`. Paths are relative to `$WORK` (`src/` = sources, `src/build/musl/` = build trees).
For the iSH-specific runtime problems see [ISH-NOTES.md](ISH-NOTES.md).

## Overall route

Upstream's `build-script --cross-compile-hosts=linux-static-aarch64` does not get through. It is used only for
what it does correctly; everything else is driven directly.

| Component | How | Stage |
|---|---|---|
| native LLVM (tblgen), cmark | `build-script` | `native` |
| LLVM / clang / lld for the musl host | the build directory `build-script` generated, reconfigured with cmake | `llvm` |
| swift-frontend for the musl host | direct cmake, `SWIFT_HOST_VARIANT_SDK=LINUX_STATIC`, `BOOTSTRAPPING_MODE=HOSTTOOLS` | `swift` |
| swift-driver, SwiftPM, macro plugin | `swift build --swift-sdk aarch64-swift-linux-musl` with the image's toolchain | `driver`, `swiftpm`, `macros` |
| stdlib / Foundation / Dispatch for the target | **not rebuilt**: the official Static Linux SDK, five objects replaced | `runtime` |
| swift-testing, SwiftPM manifest runtime | cmake, static libraries | `testing`, `swiftpm` |

Why not `build-script` all the way: for a `linux-static-*` cross host it configures the compiler itself with
`SWIFT_HOST_VARIANT_SDK=LINUX` and no toolchain file (that would be a glibc compiler), and it first builds a
complete native Swift. The image already contains the same Swift version and the musl static runtime, which is
exactly a "host toolchain + host stdlib", so HOSTTOOLS bootstrapping gets from configure to a linked
`swift-frontend` in about 20 minutes.

## build-script

- **Wrong enum name**: `StdlibDeploymentTarget.Musl` does not exist; it is `LinuxStatic`.
- **Host names with a dash**: `host_target.split('-')` breaks `linux-static-aarch64`; use `rsplit('-', 1)`.
- **No toolchain file for linux-static**: added (`CMAKE_SYSROOT=<musl-path>/<arch>`, target `<arch>-swift-linux-musl`).
- **It never reconfigures.** If `CMakeCache.txt` exists, changed `--extra-llvm-cmake-options` are silently ignored.
  The `llvm` stage runs `cmake -D… .` in the cross LLVM directory. Do not use `--reconfigure`: it also
  reconfigures and rebuilds the native LLVM.
- After editing its Python files delete `__pycache__` (the `patch` stage does).
- The `native` stage stops `build-script` as soon as the native LLVM, cmark and the cross LLVM build directory
  exist; letting it continue only builds things with the wrong configuration.
- `cc`/`c++` must be clang in the image (gcc rejects clang-only warning flags).

## LLVM for a static host

- **No shared objects at all.** The static musl `libc++abi.a` is not PIC (local-exec TLS relocations), so nothing
  can be linked as `.so`. `LLVM_ENABLE_PIC=OFF` + `LIBCLANG_BUILD_STATIC=ON` turn most of them off;
  `libIndexStore` is hard-coded `SHARED` in the Apple fork and needs the patch.
- **`LLVM_INCLUDE_TESTS` must stay ON**: later steps want the `LLVMTestingSupport` target. Three test-only
  shared objects then fail to link; the stage builds with `ninja -k` and accepts at most those three failures.
- **`alloca` undefined** when linking clang (`cc1depscan_main.cpp`): use `__builtin_alloca`.
- **Assertions**: `build-script --release` enables them, official releases do not. LLVM and Swift must agree
  (ABI); both use `LLVM_ENABLE_ASSERTIONS=OFF`.
- Only the AArch64 backend is built.

## The compiler (swift-frontend)

- Swift's CMake has no notion of a static host. The patch adds `SWIFT_HOST_IS_STATIC` and uses it to: link host
  tools with `-static -lfts`; use `lib/swift_static/linux-static` as host library directory; list the static
  runtime libraries explicitly (clang++ does the final link, so autolink entries in Swift objects are ignored);
  build swift-syntax as static libraries; drop the dlopen-based macro plugins and `SwiftInProcPluginServer` from
  the dependencies; take `SwiftShims` from the host SDK (the build machine's copy causes a module redefinition).
- **Helper tools run during the build** (`swift-compatibility-symbols`, `swift-def-to-strings-converter`,
  `swift-serialize-diagnostics`) are not in a release toolchain. Build machine and host are both aarch64 and the
  results are static, so the just-built musl binaries are executed. This is why the build needs an arm64 machine.
- **libuuid** is required by `lib/Basic` and absent from the SDK: taken from Alpine (`deps` stage), like the
  static SQLite and ncurses that llbuild needs.
- CMake's Swift compiler check cannot link for the target: `CMAKE_Swift_COMPILER_WORKS=TRUE` plus `-sdk`,
  `-resource-dir`, `-static-stdlib`, `-use-ld=lld` in the toolchain file.
- **clang links statically without being told** because the SDK installs `aarch64-swift-linux-musl-clang.cfg`
  next to clang (`-static -fuse-ld=lld -stdlib=libc++ -rtlib=compiler-rt`). The package must ship both `.cfg`
  files next to its own clang.
- A static compiler cannot `dlopen`: no `lib_InternalSwiftScan` (the wrapper passes `-nonlib-dependency-scanner`
  to swift-driver), no library macro plugins, no `.so` output.

## Replacing single objects in the SDK archives

- Containers are ephemeral and the image's SDK is pristine, so every stage that links against the runtime first
  runs `stages/patch-sdk.sh` (idempotent). There are two SDK copies: `/usr/local/musl/aarch64` (CMake builds)
  and the artifact bundle under `~/.swiftpm` (`swift build --swift-sdk`).
- **stdlib objects**: a musl-target stdlib build directory is configured but only the two objects are built. With
  `LINUX_STATIC` the combination `DYNAMIC_STDLIB=TRUE/STATIC=FALSE` is the one that configures (the other way
  round produces duplicate custom rules).
- **libdispatch objects** need `-D_GNU_SOURCE` (otherwise the `getprogname` check fails) and
  `-mno-outline-atomics` (otherwise the objects reference `__aarch64_cas*` helpers the official ones do not).
- **CoreFoundation** has no cheap standalone configure, so `CFPlatform.c` is compiled directly with the flags from
  the official CMake files (`-D_GNU_SOURCE -DDEPLOYMENT_RUNTIME_SWIFT -DCF_BUILDING_CF … -fcf-runtime-abi=swift`,
  prefix header included).
- **How equivalence was checked**: `llvm-nm` of the rebuilt object against the official member. Each differs only
  by the functions the patch introduces; data and bss sizes are identical. An unmodified file rebuilt this way
  has an identical symbol table.

## Macro plugin

- The compiler loads `-load-plugin-executable <path>#Module,Module…` plugins over a pipe; no `dlopen` involved.
- `CompilerPlugin` resolves macros by `"<Module>.<Type>"` using `String(reflecting:)`, so the SwiftPM target names
  must equal the official module names (`SwiftMacros`, `ObservationMacros`, `FoundationMacros`, `TestingMacros`).
- `swift-testing/Sources/TestingMacros` contains a symlink into `_TestDiscovery`; copy with `cp -RL`.
- `CompilerPlugin.main()` throws: `try BuiltinMacros.main()` at top level.

## swift-testing

- Not part of the Static Linux SDK. Built with CMake as static libraries; the macros needed to compile the
  library itself come from the build machine's `libTestingMacros.so`.
- musl source fixes: `RLIMIT_CORE` type, optional `pthread_t`, `siginfo_t` accessors, no `backtrace()`.
- The sysroot has no kernel headers; `files/testing-shim/linux/fs.h` defines only `FICLONE`.
- Its non-public imports (Synchronization, Foundation, Dispatch) give static clients no autolink entries: a file
  that only says `import Testing` failed to link. Fixed with `-public-autolink-library` when building it.
- **Library evolution for every module.** Upstream's CMake enables it only for `Testing`. `_Testing_Foundation`
  (the cross-import overlay loaded when a file imports both Testing and Foundation, which SwiftPM test targets
  do via `-enable-cross-import-overlays`) then records the internal C module `_TestingInternals` as a required
  dependency: `error: missing required modules: '_TestingInternals.StubsOnly', '_TestingInternals'`.
- **Binary modules only.** A `.swiftmodule` with a `.swiftinterface` next to it is validated against the
  dependency paths and mtimes of the build machine, judged out of date, and the interface is silently recompiled
  on the device into every new module cache. The interfaces of Testing and of SwiftPM's PackageDescription modules
  are therefore not shipped. (Check: no `Testing-*.swiftmodule` may appear in `.build/debug/ModuleCache`.)

## SwiftPM

- **pkg-config leak**: the manifest's `pkgConfig: "sqlite3"` adds the build machine's
  `-L/usr/lib/aarch64-linux-gnu`, and the link then picks up glibc's `libc.a` and `libcurl.a`. The manifest's only
  switch for this is `SWIFTCI_INSTALL_RPATH_OS=android` (the rpath flags it adds are no-ops for a static link).
- **Swift Build backend** (the default in 6.4) fails at startup with `Could not locate shared object for
  pointer` (`dladdr`). Patched default: native build system when the host is musl.
- **Which `swiftc`**: the native build system forks the `swiftc` in its own directory. Therefore `bin/swiftc`
  itself is the wrapper. Pointing `SWIFT_EXEC` elsewhere breaks feature detection (it looks for `swift-frontend`
  next to that path) and tests then fail to link with `duplicate symbol: main`.
- **Legacy driver** does not know `-incremental` (SwiftPM always passes it); the wrapper drops it.
- **Manifests are linked statically** against `libPackageDescription.a`. That module imports Foundation
  implementation-only, so Foundation's libraries are recorded with `-public-autolink-library`.
- **XCTest discovery** dlopens libIndexStore. Patched to emit empty discovery sources when the library cannot be
  loaded; there is no XCTest library for the static SDK anyway.
- **128 KB thread stacks**: `swift test` segfaulted while decoding options on a libdispatch worker. Linked with
  `-z stack-size=8388608`.
- **`Bundle.main`**: see ISH-NOTES.md, item 1.

## Layout and wrappers

- The musl sysroot is merged into the prefix (`include/`, `lib/*.a`), and the wrapper passes the prefix as `-sdk`.
  clang accepts `<sysroot>/include` and `<sysroot>/lib` besides the `usr/` variants, and finds the libc++ headers
  relative to its own binary. The Swift drivers, however, look for the static resource directory at
  `<sdk>/usr/lib/swift_static` when `-sdk` is given: the legacy driver is therefore run with an explicit
  `-resource-dir <prefix>/lib/swift_static` (which needs a `shims` link inside `swift_static`), and swift-driver
  — which ignores `-resource-dir` for `swiftrt.o` — is run without `-sdk` and gets
  `-Xcc --sysroot=<prefix> -Xclang-linker --sysroot=<prefix>` instead.
- `lib/swift` is completed with links to every directory of `lib/swift_static`: the legacy driver's
  merge-modules job (used with `-g`) does not pass the static resource directory and otherwise fails with
  `cannot load underlying module for 'Dispatch'`.
- The legacy driver runs `ar` for static libraries. To avoid shipping `bin/ar`, a link to `llvm-ar` lives in
  `lib/swift/toolbin`, which the wrapper appends to `PATH`.
- Linking adds `--gc-sections -s` unless `-g` is on the command line or `SWIFTC_KEEP_SYMBOLS` is set, and
  `-z stack-size=8388608` unless `SWIFTC_STACK_SIZE=0` (musl reads the default thread stack size from `PT_GNU_STACK`).
- `SWIFT_AVOID_WARNING_USING_OLD_DRIVER` silences the legacy driver's deprecation warning.

## ICU data

- 34 MB of the 54 MB "hello Foundation" binary is ICU's common data, embedded in
  `lib_FoundationICU.a(icu_packaged_data.cpp.o)` as one symbol.
- `files/icu-trim/extract.py` recovers the `.dat` from the four `.inc.h` chunks in swift-foundation-icu;
  `icudat.py` parses and rebuilds the package; `make_profiles.py` selects entries; the `icu` stage wraps the
  result with `.incbin` into an object defining the same symbol. Passed to the linker before the archives, it
  keeps the full-data member from being pulled in. No library is modified.
- Size by category: converters 5.7 MB, collation 4.3, top-level locales 4.1, break iteration 3.8 (CJK dictionary
  2.0), zone / unit / currency / language names about 3 MB each.
- `res_index` is not rewritten, so `Locale.availableIdentifiers` still lists removed locales (they resolve to root).
- `--icf` gains nothing (the official archives carry no address-significance tables); `--compress-sections`
  needs an lld with zstd.

## Debugging silent traps

`strace -f` to get the faulting address from the SIGTRAP line, then `llvm-symbolizer -e <unstripped binary> <addr>`.
That is how the empty `CommandLine.arguments` (swift-driver) and the `Bundle.main` trap (SwiftPM) were found; the
stack overflow showed up in gdb as a 60-frame decoding chain on a `DispatchWorker` thread.

## Not done

- LLDB, sourcekit-lsp, XCTest, a REPL.
- An x86_64 variant: the same route should work, but the "run just-built helper tools" shortcut needs native
  builds of those three tools first.
- User-defined macro packages and SwiftPM build plugins are untested.
