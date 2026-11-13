# Why the patches exist: what iSH does differently

iSH runs Linux binaries on iOS through its own user-space implementation of the Linux system-call interface and
of `/proc`. A statically linked Swift toolchain exercises corners of that interface that most command-line
programs never touch. This file records what was observed on the device, how each behaviour was confirmed or
reproduced, and which patch answers it. Build problems are in [NOTES.md](NOTES.md).

Legend for the "status" lines: **measured on iSH** = observed on the device; **reproduced** = the same failure was
produced on a regular Linux kernel by removing the facility; **inferred** = consistent with the evidence but not
measured directly.

## 1. `readlink("/proc/self/exe")` fails intermittently

- **Symptom.** Any program touching the Swift concurrency runtime (`Task {}`, `withTaskGroup`, actors) died in
  about 95% of runs with `Unable to obtain Swift runtime path` / `Aborted` (exit 134). The same binary never
  failed in an Alpine container.
- **Measured on iSH** with a static C test: three rounds of 2000 `readlink("/proc/self/exe")` calls failed
  0/2000, 2000/2000 and 610/2000 times; concurrent readers failed more often. `getauxval(AT_EXECFN)` returned a
  usable path in 4000 of 4000 calls (it may be relative, e.g. `./prog`).
- **Why Swift cares.** In a static executable `dladdr()` returns nothing, so several components fall back to
  `/proc/self/exe` to find out where they live, and treat failure as fatal or as "no path":

  | Component | Code | Old behaviour | Patch |
  |---|---|---|---|
  | Swift runtime | `stdlib/public/runtime/Paths.cpp` | `fatalError` | `swift/0003` — retry, `AT_EXECFN`, `argv[0]`/`PATH`, else null |
  | LLVM (clang, lld, swift-frontend) | `llvm/lib/Support/Unix/Path.inc` | returns `""` → resource dir, config file, `ld.lld` not found | `llvm-project/0002` — retry, then the existing `argv[0]` logic |
  | CoreFoundation | `CFPlatform.c` `_CFProcessPath` | `""` → no main bundle → `Bundle.main` traps | `swift-corelibs-foundation/0001` — retry, `AT_EXECFN` |
  | swift-driver | `Toolchain.executableDir` | `fatalError` when `Bundle.main` has no path | `swift-driver/0001` — prefer `argv[0]` |

- **Reproduced** by running everything in a chroot without `/proc` (`tests/hostile.sh`): the unpatched runtime
  fails every time, the patched toolchain compiles and runs the whole self test.

## 2. `/proc/self/maps` and `CommandLine.arguments`

- On musl the Swift runtime has no `__libc_argv`-style hook; it finds `argv` by reading `/proc/self/maps` to locate
  the main thread's stack and walking back from `environ`. If the file cannot be read the argument array is
  empty, and code indexing `arguments[0]` traps. swift-driver crashed this way.
- **Status: reproduced** (no-`/proc` chroot); on iSH itself this was not isolated from problem 1.
- **Patch** `swift/0004`: when the stack bounds are unknown, walk down from `environ[-1] == NULL` counting slots
  until a slot holds the count (that slot is `argc`). It only depends on the initial process stack layout.

## 3. No priority-inheritance futexes

- **Symptom.** After problem 1 was fixed, `Task { 42 }` passed 20/20 but `withTaskGroup` / actor programs still
  failed 20–55% of the time with a silent `Trace/breakpoint trap` (exit 133) and no message.
- **Cause.** libdispatch's unfair lock is a compare-and-swap in the uncontended case and
  `FUTEX_LOCK_PI` / `FUTEX_UNLOCK_PI` under contention. Any error other than the expected ones is a
  `DISPATCH_INTERNAL_CRASH`, i.e. a `brk` instruction. Contention on the worker-thread registry lock is exactly
  what several concurrent tasks produce, and a single task does not.
- **Status: inferred for iSH, reproduced elsewhere.** Blocking only the PI futex operations with seccomp
  (`tests/seccomp-nofutexpi.json`, operations 6/7/8 return `ENOSYS`) makes the unpatched runtime fail in the same
  pattern (13–17 of 20 runs passing, all failures exit 133). Whether iSH returns `ENOSYS` or another error for
  these operations was not measured; a two-line C test (`syscall(SYS_futex, &word, FUTEX_LOCK_PI|FUTEX_PRIVATE_FLAG,
  0, 0, 0, 0)` and print `errno`) would settle it.
- **Patch** `swift-corelibs-libdispatch/0001`: a three-state probe. If the first PI call fails with
  `ENOSYS`/`EINVAL`/`ENOTSUP` and no PI call ever succeeded, the lock becomes a `sched_yield()` spin lock for the
  life of the process. Once a PI call has succeeded nothing changes.
- The Swift runtime's own mutex also uses PI futexes but retries its CAS loop on failure, so it degrades to
  spinning by itself and needed no change.

## 4. `/proc/<tid>/stat` in the libdispatch thread-pool monitor

- libdispatch periodically opens `/proc/<tid>/stat` of each worker to count runnable threads; a failed `open` is
  a `DISPATCH_CLIENT_CRASH` (again a silent SIGTRAP).
- **Measured on iSH:** reading another thread's `/proc/<tid>/stat` succeeded 3200 of 3200 times, so this is
  probably not what failed on the device. **Reproduced** without `/proc`, where it is certain to crash.
- **Patch** `swift-corelibs-libdispatch/0002`: an unreadable entry is not counted. Kept as defence in depth.

## 5. The Swift-written driver hangs sometimes

- **Measured on iSH:** `swift-driver` (the default driver upstream) occasionally hangs when compiling with `-g`.
  The cause is unknown. It spawns more processes and threads than the older C++ driver and uses llbuild to
  schedule them.
- **Not patched.** The package sidesteps it: `swiftc` runs the legacy C++ driver that is built into
  `swift-frontend` by default (`SWIFTC_DRIVER=new` selects swift-driver). SwiftPM's native build system starts
  the `swiftc` next to it for every compile and link step, so it goes through the same wrapper and the same
  driver.

## 6. Thread stacks (musl, not iSH)

- musl's default stack for non-main threads is 128 KB (glibc: 8 MB). Swift tasks run on libdispatch workers.
  SwiftPM overflowed it while decoding its command-line options (`swift test` segfaulted in an Alpine
  container, no iSH involved).
- **Measured on iSH:** 400 concurrent tasks each recursing 20000 levels segfaulted in 8 of 8 runs with the
  default stack and with 1 MB, and passed 8 of 8 with 8 MB; 10000 tasks ran stably with 8 MB stacks, so the larger
  virtual reservation is not a problem there.
- **Fix:** SwiftPM is linked with `-z stack-size=8388608`, and the `swiftc` wrapper adds the same to every program
  it links (`SWIFTC_STACK_SIZE=0` disables it); musl takes the default thread stack size from `PT_GNU_STACK`.

## 7. Open: many sleeping tasks sometimes stall

- **Measured on iSH:** a task group with 1000+ tasks that each `Task.sleep` for 1 ms stalls for more than 30 s in
  about half of the runs (no crash); 10000 tasks without sleep always finish. Stack size is irrelevant.
- **Not reproduced** on a regular kernel, with or without PI futexes (1000–20000 tasks, 0 stalls), and not patched.
- libdispatch's timer path (`src/event/event_epoll.c`) assumes: a `timerfd_settime(TFD_TIMER_ABSTIME)` whose target
  is already in the past fires at once; re-arming clears a pending expiration without `read()`; the timerfd is
  registered `EPOLLONESHOT` and re-armed with `EPOLL_CTL_MOD`, which must report an fd that is already readable;
  `CLOCK_BOOTTIME` timerfds work; the manager thread is woken through an eventfd. `tests/timer-probe.c` checks
  each of these and passes on Linux; its result on the device decides what, if anything, to change.

## Still unprotected

These paths would also crash if the kernel interface misbehaved, but nothing suggests iSH does:
libdispatch's `epoll` / `eventfd` / `timerfd` / `signalfd` setup, unexpected errors from plain
`FUTEX_WAIT` / `FUTEX_WAKE`, and `sem_*` failures.

## Reproducing without a device

```sh
./build.sh <tag> --only selftest --hostile
```

runs the self test once normally and once in a chroot that has no `/proc`, inside a container whose seccomp
profile rejects PI futexes. This is stricter than iSH (which has a `/proc`, just an unreliable one) and is not a
substitute for testing on the device.
