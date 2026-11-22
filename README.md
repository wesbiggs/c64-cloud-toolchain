# c64-cloud-toolchain

[cc65](https://cc65.github.io) and a headless
[VICE](https://vice-emu.sourceforge.io) for building and testing Commodore
64 programs on a machine with no screen: a GitHub Actions runner, a Claude
Code cloud session, a container. One script, `setup.sh`, for Ubuntu 24.04,
and a GitHub Action that runs it and caches the result.

What you get, on the `PATH` (linked into `/usr/local/bin`):

- **cc65 2.19**: `cl65`, `ca65`, `ld65`, `ar65` and the rest.
- **VICE 3.10, headless**: `x64sc`, `c1541`, `petcat` and the other
  emulators and tools, with no window and no display server, and the C64's
  and the drives' ROMs included (Ubuntu's own VICE package leaves the ROMs
  out).

Each release builds both from source on `ubuntu-24.04` into
`/opt/c64-toolchain` and publishes them as one tarball, so setting up takes
seconds instead of minutes.

## In GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v5
  - uses: wesbiggs/c64-cloud-toolchain@v1.0.0
    with:
      packages: python3-pil   # optional: extra apt packages
  - run: make && make test
```

The toolchain is kept in your repository's Actions cache, keyed by the
release, so after the first run it is restored in a few seconds. A miss
downloads the release's tarball, and if that cannot be had, builds from
source (so CI never runs a different VICE). `cache: false` turns the cache
off.

## In a cloud session or a container

Run the script as root, from a pinned release:

```sh
curl -fsSL https://raw.githubusercontent.com/wesbiggs/c64-cloud-toolchain/v1.0.0/setup.sh \
  | sudo sh -s -- python3-pil
```

For a Claude Code cloud environment, put that in the environment's setup
script. The script is self-contained, so you can also copy it into your
project. It is safe to run again: whatever is already set up is left alone.

If GitHub's release downloads are blocked, the script falls back to Ubuntu's
own cc65 (2.19, which calls itself V2.18) and VICE (3.7, the GTK build),
fetches the ROMs from VICE's source tarball (or from VICE's GitHub mirror)
and checks them against their checksums, and installs an `x64sc` wrapper that
starts Xvfb when there is no display. Environment variables change this:

| variable | |
|---|---|
| `C64TC_FALLBACK=source` | build cc65 and VICE from source instead of using Ubuntu's (a few minutes) |
| `C64TC_FALLBACK=none` | fail instead |
| `C64TC_PREBUILT=0` | skip the download and go straight to the fallback |
| `C64TC_FROM_SOURCE=1` | build from source, as the release does |

## VICE 3.10's log crash, fixed here

An unpatched VICE 3.10 crashes at startup (a segmentation fault, before the
machine runs) whenever its output goes to a file or a pipe rather than a
terminal or `/dev/null` -- which is where a CI log puts it. It logs that the
CMD drives' ROMs are missing, and the code that strips the log's colours
for a non-terminal reads a string it never made. The release's VICE is
built with that line fixed. With another VICE 3.10, pass `+logcolorize`
(no colours in the log) to avoid it.

## Checking it works

`test/run.sh` builds `test/hello.c` with `cl65`, writes it to a disk image
with `c1541`, and boots it in `x64sc` from the disk through the 1541's own
ROM. The program checks the screen and the character ROM and reports back
through VICE's debug cartridge (`-debugcart`, a write to `$D7FF` becomes the
emulator's exit code), so the script exits 0 only if all of it works. That
pattern is also a simple way to write your own headless tests.

## Making a release

1. Set `RELEASE=` in `setup.sh` to the new tag (and the versions, if they
   changed), and update the tag in this README.
2. Commit, then tag that commit with the same name and push the tag.
3. `.github/workflows/release.yml` builds from source, runs the smoke test,
   publishes the tarball to the release, and checks a fresh runner can
   download and use it.

The tag must match `RELEASE`, because that is how the script at a given tag
knows which tarball is its own. Projects then move to the new tag when they
are ready.

## Licence

MIT (`LICENSE`). cc65 and VICE keep their own licences (zlib and GPL-2.0
respectively). The release tarball's cc65 is built unmodified from its
`V2.19` tag, and its VICE from the 3.10 source release with the one-line
fix described below; `setup.sh` (`patch_vice()`) is the whole of the
change, and the sources are those releases.
