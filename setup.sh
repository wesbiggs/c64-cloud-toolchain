#!/bin/sh
# SPDX-License-Identifier: MIT
# c64-cloud-toolchain: make a fresh Ubuntu 24.04 machine -- a Claude Code
# cloud session, a GitHub Actions runner, a container -- able to build
# Commodore 64 programs with cc65 and run them headless in VICE.
#
#   sudo ./setup.sh [APT-PACKAGE...]
#
# Any arguments are extra apt packages a project wants too (python3-pil,
# say). Safe to run again: what is already there is left alone.
#
# cc65 and VICE, in order of preference:
#
# 1. This release's prebuilt toolchain: cc65 $CC65_VERSION and the headless
#    VICE $VICE_VERSION (no window, no display server, the ROMs included),
#    built on ubuntu-24.04 into $PREFIX and published as a release asset of
#    this repository by .github/workflows/release.yml. A public download,
#    no token: github.com and its release-assets host must be reachable.
# 2. If that cannot be had, C64TC_FALLBACK says what then:
#    "ubuntu" (the default): Ubuntu's own cc65 (2.19, which calls itself
#       V2.18) and VICE (3.7, the GTK build) plus the C64 and drive ROMs out
#       of VICE $VICE_VERSION's source tarball. The package leaves the ROMs
#       out as non-free, so they are put where it looks, /usr/share/vice,
#       and checked against the checksums below. The GTK build wants a
#       display, so /usr/local/bin/x64sc is a wrapper that starts Xvfb on
#       :99 when there is no $DISPLAY. The tarball is from SourceForge; if
#       that is blocked, the ROMs come from VICE's GitHub mirror
#       (raw.githubusercontent.com, VICE-Team/svn-mirror), the same bytes.
#    "source": build both from source into $PREFIX, as the release does (a
#       few minutes; the GitHub Action uses this, so CI always runs VICE
#       $VICE_VERSION).
#    "none": fail.
#    C64TC_FROM_SOURCE=1 skips the download and builds from source;
#    C64TC_PREBUILT=0 skips the download and takes the fallback.
#
# What is in $PREFIX is linked into /usr/local/bin, so every shell finds it
# however it was started, and a tool that follows the x64sc link back finds
# the ROMs in $PREFIX/vice/share/vice.
set -eu

RELEASE=v1.0.1
REPO=wesbiggs/c64-cloud-toolchain
VICE_VERSION=3.10
CC65_VERSION=2.19
PREFIX=/opt/c64-toolchain
ASSET=c64-toolchain-ubuntu24.04-x86_64.tgz
URL=https://github.com/$REPO/releases/download/$RELEASE/$ASSET
TARBALL=https://sourceforge.net/projects/vice-emu/files/releases/vice-$VICE_VERSION.tar.gz/download
MIRROR=https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/data
CC65_GIT=https://github.com/cc65/cc65.git
VICEDATA=/usr/share/vice

# The ROMs a C64 with a 1541 or a 1581 boots from, as VICE $VICE_VERSION
# ships them.
ROMS="
83c60d47047d7beab8e5b7bf6f67f80daa088b7a6a27de0d7e016f6484042721  C64/kernal-901227-03.bin
89878cea0a268734696de11c4bae593eaaa506465d2029d619c0e0cbccdfa62d  C64/basic-901226-01.bin
fd0d53b8480e86163ac98998976c72cc58d5dd8eb824ed7b829774e74213b420  C64/chargen-901225-01.bin
d1d45afb46fd4e2b48d93ca367b889d75654a3b7acf73044e51f6d880c09369e  DRIVES/dos1541-325302-01+901229-05.bin
8f689277f36be357f5f105e6e606c35c42e73c581cdeec14b58f31850dfbcfcb  DRIVES/dos1581-318045-02.bin
"

SUDO=
[ "$(id -u)" = 0 ] || SUDO=sudo

say() { echo "c64-cloud-toolchain: $*"; }

# Try without an update first: it is slow, and the image's lists are
# usually fresh enough.
apt_install() {
    $SUDO apt-get install -y -q --no-install-recommends "$@" >/dev/null 2>&1 \
    || { $SUDO apt-get update -q >/dev/null \
         && $SUDO apt-get install -y -q --no-install-recommends "$@" >/dev/null; }
}

have_prefix() {
    [ -x "$PREFIX/vice/bin/x64sc" ] && [ -x "$PREFIX/cc65/bin/cl65" ]
}

fetch_prebuilt() {
    command -v curl >/dev/null 2>&1 || apt_install curl ca-certificates
    # Into a scratch directory first, so a download cut short leaves no
    # half an install behind to be mistaken for a whole one.
    tmp=$(mktemp -d)
    if curl -fsSL "$URL" | tar -xz -C "$tmp" \
       && [ -x "$tmp$PREFIX/vice/bin/x64sc" ]; then
        $SUDO mkdir -p "$PREFIX"
        $SUDO rm -rf "$PREFIX/vice" "$PREFIX/cc65"
        $SUDO mv "$tmp$PREFIX"/* "$PREFIX/"
        rm -rf "$tmp"
        say "toolchain $RELEASE from the release"
        return 0
    fi
    rm -rf "$tmp"
    say "no $ASSET from release $RELEASE"
    return 1
}

build_cc65() {
    say "building cc65 $CC65_VERSION from source"
    src=$(mktemp -d)
    git clone -q --depth 1 --branch "V$CC65_VERSION" "$CC65_GIT" "$src/cc65"
    make -s -C "$src/cc65" -j"$(nproc)" PREFIX="$PREFIX/cc65" >/dev/null
    $SUDO make -s -C "$src/cc65" install PREFIX="$PREFIX/cc65" >/dev/null
    rm -rf "$src"
}

# VICE 3.10 crashes at startup when its log goes anywhere but a terminal or
# /dev/null -- a file, a pipe, a CI log -- as soon as it logs anything (a
# drive ROM it does not have, the CMD drives', always): log_helper() makes
# the log's colourless copies only for a log file or with colours off, then
# hands them to stdout when stdout is not a terminal, and strlen(NULL)
# faults. Making them every time is the fix; +logcolorize avoids it in an
# unpatched VICE. Refuses to build if the line is not there to patch.
patch_vice() {
    old='    if ((log_to_file) || (!log_colorize)) {'
    grep -qxF "$old" src/log.c || {
        say "src/log.c has changed: check the log patch in setup.sh"; exit 1; }
    sed -i 's/^    if ((log_to_file) || (!log_colorize)) {$/    {   \/* c64-cloud-toolchain: always, for a stdout that is not a terminal *\//' \
        src/log.c
    grep -q 'c64-cloud-toolchain: always' src/log.c
}

build_vice() {
    say "building VICE $VICE_VERSION from source (a few minutes)"
    src=$(mktemp -d)
    curl -fsSL -o "$src/vice.tgz" "$TARBALL"
    tar -xzf "$src/vice.tgz" -C "$src"
    (
        cd "$src/vice-$VICE_VERSION"
        patch_vice
        ./configure --prefix="$PREFIX/vice" --enable-headlessui \
            --disable-html-docs --without-pulse --without-alsa \
            --without-png --without-libcurl >/dev/null
        make -j"$(nproc)" >/dev/null
        $SUDO make install >/dev/null
    )
    rm -rf "$src"
}

build_all() {
    apt_install build-essential pkg-config flex bison dos2unix xa65 \
        texinfo curl git ca-certificates
    [ -x "$PREFIX/cc65/bin/cl65" ] || build_cc65
    [ -x "$PREFIX/vice/bin/x64sc" ] || build_vice
    printf 'release %s\ncc65 %s\nvice %s headless\n' \
        "$RELEASE" "$CC65_VERSION" "$VICE_VERSION" \
        | $SUDO tee "$PREFIX/VERSION" >/dev/null
}

roms_ok() {
    (cd "$VICEDATA" && printf '%s' "$ROMS" | grep . | sha256sum -c --quiet -) \
        >/dev/null 2>&1
}

# Every C64 and drive ROM in the release's data/, so that any model VICE
# is asked for is there; from the mirror, only the ones in $ROMS.
fetch_roms() {
    tmp=$(mktemp -d)
    if curl -fsSL -o "$tmp/vice.tgz" "$TARBALL" \
       && tar -xzf "$tmp/vice.tgz" -C "$tmp" --wildcards \
              "vice-$VICE_VERSION/data/C64/*.bin" \
              "vice-$VICE_VERSION/data/DRIVES/*.bin"; then
        say "ROMs from the VICE $VICE_VERSION source tarball"
        for d in C64 DRIVES; do
            $SUDO mkdir -p "$VICEDATA/$d"
            $SUDO cp "$tmp/vice-$VICE_VERSION/data/$d/"*.bin "$VICEDATA/$d/"
        done
    else
        say "no tarball from SourceForge; ROMs from VICE's GitHub mirror"
        printf '%s' "$ROMS" | grep . | while read -r _ rom; do
            $SUDO mkdir -p "$VICEDATA/${rom%/*}"
            curl -fsSL "$MIRROR/$rom" | $SUDO tee "$VICEDATA/$rom" >/dev/null
        done
    fi
    rm -rf "$tmp"
    roms_ok || { say "the ROMs do not match their checksums"; exit 1; }
}

# Ubuntu's x64sc is the GTK build and will not start without a display.
# Started once and left running; exec keeps the pid, so a harness's kill
# reaches the emulator itself.
install_wrapper() {
    $SUDO tee /usr/local/bin/x64sc >/dev/null <<'WRAP'
#!/bin/sh
# Ubuntu's x64sc, on a virtual display when there is no real one
# (written by c64-cloud-toolchain's setup.sh).
if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=:99
    if [ ! -S /tmp/.X11-unix/X99 ] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
        setsid Xvfb :99 -screen 0 1024x768x24 -nolisten tcp \
            >/dev/null 2>&1 </dev/null &
    fi
    i=0
    while [ ! -S /tmp/.X11-unix/X99 ] && [ $i -lt 100 ]; do
        sleep 0.1; i=$((i + 1))
    done
fi
exec /usr/bin/x64sc "$@"
WRAP
    $SUDO chmod 755 /usr/local/bin/x64sc
}

ubuntu_toolchain() {
    command -v cl65 >/dev/null 2>&1 || { say "installing Ubuntu's cc65"; \
        apt_install cc65; }
    [ -x /usr/bin/x64sc ] || { say "installing Ubuntu's VICE"; \
        apt_install vice xvfb curl ca-certificates; }
    command -v Xvfb >/dev/null 2>&1 || apt_install xvfb
    roms_ok || fetch_roms
    install_wrapper
}

ubuntu_done() {
    [ -x /usr/bin/x64sc ] && [ -x /usr/local/bin/x64sc ] \
        && command -v cl65 >/dev/null 2>&1 && roms_ok
}

if [ "${C64TC_FROM_SOURCE:-0}" = 1 ]; then
    have_prefix || build_all
elif have_prefix || ubuntu_done; then
    :
elif [ "${C64TC_PREBUILT:-1}" = 0 ] || ! fetch_prebuilt; then
    case ${C64TC_FALLBACK:-ubuntu} in
        source) build_all ;;
        ubuntu) ubuntu_toolchain ;;
        none) exit 1 ;;
        *) say "C64TC_FALLBACK is ubuntu, source or none"; exit 1 ;;
    esac
fi

if have_prefix; then
    for tool in "$PREFIX"/cc65/bin/* "$PREFIX"/vice/bin/*; do
        $SUDO ln -sf "$tool" "/usr/local/bin/${tool##*/}"
    done
fi

[ $# -eq 0 ] || { say "installing $*"; apt_install "$@"; }

say "$(cl65 --version 2>&1 | head -1)"
say "$(x64sc --version 2>&1 | grep -m1 -i vice)"
