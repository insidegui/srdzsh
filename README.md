# zsh for Apple Security Research Device

This project cross-compiles zsh 5.9.2 for arm64e iOS and assembles a root
directory suitable for `srdtool cryptex install`.

The build pins the official zsh archive by SHA-256, grafts the ncurses headers
that Apple ships in the macOS SDK but omits from the public iPhoneOS SDK, and
links supported zsh modules statically into one ad-hoc-signed executable.
Static linking is intentional: ZLE, completion, key maps, terminfo, PTYs, and
the other standard modules do not depend on unsigned loadable bundles or a
fixed cryptex mount path.

## Requirements

- macOS with Xcode and the iPhoneOS SDK
- `make`, `curl`, `patch`, and the standard macOS command-line tools
- Apple's `srdtool` (the default path is
  `../security-research-device/bin/srdtool`)

## Build and verify

```sh
make
make check
```

The result is `zsh-cryptex.root/`.  The cryptex includes the complete upstream
completion function set, common compiled terminfo entries, and small global
startup files that enable persistent history, completion, and reliable
terminal key bindings.

The default target is arm64e with an iOS 15.0 deployment target.  Both are
overridable:

```sh
make ARCH=arm64e IOS_MIN_VERSION=17.0
```

## Install

Configure `srdtool` for the device first, then run:

```sh
make install
```

By default this installs a persistent cryptex named `com.research.zsh`.
Common overrides are:

```sh
make install CRYPTEX_IDENTIFIER=com.example.zsh
make install ECID=0x123456789abcdef
make install SRDTOOL=/path/to/srdtool
make install SRDTOOL_INSTALL_FLAGS=
```

`CRYPTEX_MOUNT_PATH` should be preserved when launching zsh from another
cryptex tool such as the SRD example's patched dropbear.  The bundled global
`zshenv` uses it to locate completion functions and terminfo data inside the
randomized cryptex mount.  If the cryptex is visible through an absolute
overlay path, zsh also works with its compiled `/usr/share/zsh` paths.

The `zsh/zftp` module is not included because it depends on the obsolete
`<arpa/telnet.h>` header, which is absent from the iPhoneOS SDK.  Modern
`zsh/net/tcp` and `zsh/net/socket` support is included.
