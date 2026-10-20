# ish-pkgs

Prebuilt binaries for **iSH** (the ARM64 guest in [Minis](https://github.com/OpenMinis/ish-arm64)),
published as a signed **apk repository**. Plain `apk` is the only client you need.

> This is a collection of **third-party software rebuilt for iSH**, not original work.
> Each package says exactly which upstream tag it was built from and whether anything was changed.

## Install

Architecture: **aarch64 only** (the ARM64 iSH guest). The original x86 iSH guest is not supported.

```sh
# 1) trust the repository key (once)
wget -O /etc/apk/keys/ish-pkgs.rsa.pub \
  https://raw.githubusercontent.com/OpenMinis/ish-pkgs/main/ish-pkgs.rsa.pub

# 2) add the repository (once)
echo "https://raw.githubusercontent.com/OpenMinis/ish-pkgs/main" >> /etc/apk/repositories

# 3) install
apk update
apk add pair-host            # just pair_host (~0.85 MB)
apk add idevice-tools        # the rest of idevice-tools; pulls in pair-host
```

Verify the key you downloaded before trusting it:

```
sha256(ish-pkgs.rsa.pub) = 2db5bb598e9b98596be896a43117d4614e8c07f243ba476eeee9d89679022fdd
```

Updating is the normal apk flow: `apk update && apk upgrade`.

## Status

> **Work in progress: the signed package index is not published yet.**
> This repository currently holds the build/packaging tooling and the signing public key only.
> `apk add pair-host` will not work until `aarch64/` (the `.apk` files and the signed `APKINDEX.tar.gz`)
> has been built from a clean build and committed. Check the commit history for when that lands.

## Packages

| package | contents | upstream |
|---|---|---|
| `pair-host` | `pair_host`: advertise as an iOS 27 pairable host and write a pairing file | [jkcoxson/idevice](https://github.com/jkcoxson/idevice) (MIT) |
| `idevice-tools` | `idevice-tools`, `idevice_id`, `iproxy`, `pair_apple_tv` (depends on `pair-host`) | same |

`apk del idevice-tools` also removes `pair-host` unless you installed it explicitly (`apk add pair-host`).

### Notes that matter in iSH

- `idevice_id` and `iproxy` expect a running **usbmuxd**. iSH has none, so `idevice_id` aborts at start
  (`unwrap()` on a missing socket; upstream builds with `panic = "abort"`). This is upstream behaviour.
- `pair_host` advertises over mDNS with raw multicast. On iOS that needs the
  `com.apple.developer.networking.multicast` entitlement, so **from inside the iOS app the advertisement
  does not leave the phone**. Use it on a Mac/Linux host, or have the app publish the service
  (see `minis-bonjour`) and run `pair_host` for the protocol part.

## How binaries are built

Everything is reproducible from this repo:

```sh
pkgs/idevice-tools/update.sh                      # is there a newer upstream tag? (read-only)
pkgs/idevice-tools/build.sh v0.1.68 dist          # cross-compile on macOS/Linux (needs rustup + zig)
tools/publish.sh dist/idevice-tools-ish-arm64-v0.1.68.zip v0.1.68    # apk packages + signed index
```

- `build.sh` fetches the **upstream tag**, applies `pkgs/<name>/patches/*.patch` (if any), cross-compiles
  for `aarch64-unknown-linux-musl` with `zig cc`, and keeps the same executables the upstream CI ships.
- The zip layout mirrors upstream: `idevice-tools-ish-arm64-<tag>.zip` next to upstream's
  `idevice-tools-linux-<tag>.zip`, flat, same file names.
- Every package carries `/usr/share/doc/<pkg>/PROVENANCE.txt`: upstream URL, tag, commit, toolchain,
  sha256 of each file, and either `modifications: NONE` or the list of patches applied.
- The build is **reproducible**: the `pair_host` built from tag `v0.1.68` is byte-identical to the one
  built earlier from a later main commit that did not touch it.

### Current builds

| package | version | upstream | commit | modifications |
|---|---|---|---|---|
| `pair-host`, `idevice-tools` | `0.1.68-r0` | `v0.1.68` | `d32c8189` | none |

Version scheme: `<upstream version>-r<N>`. `N` increases when we rebuild or patch without an upstream change.

## Trust model

- The **index** is signed with an RSA-4096 key (same scheme as Alpine's own repositories: RSA over the
  SHA-1 of the compressed index). Individual `.apk` files are not signed; they are bound to the signed index
  by the checksum stored in it.
- apk refuses the repository until you install the public key, so a tampered index is rejected.
- A signature here only means "published by OpenMinis". It does **not** mean "published by upstream".
- The private key lives only on the maintainer's device and is never committed (`.gitignore` blocks it).
  If it ever changes, this README and the fingerprint above change with it.

## Layout

```
ish-pkgs.rsa.pub                  public key (private key is never in git)
aarch64/APKINDEX.tar.gz           signed index
aarch64/*.apk                     packages
pkgs/<name>/UPSTREAM              upstream URL + the tag currently built
pkgs/<name>/build.sh update.sh    build and update scripts
pkgs/<name>/patches/              our patches, if any (none yet)
pkgs/<name>/LICENSE.upstream      upstream license, kept as required
tools/mkapk.py mkrepo.py          pure-Python apk packer and index signer (no abuild needed)
tools/publish.sh                  build zip -> .apk -> signed index
```

## License

Scripts and docs: MIT (see `LICENSE`). Binaries: each upstream's own license; for `idevice-tools` that is MIT,
copyright Jackson Coxson (`pkgs/idevice-tools/LICENSE.upstream`).
