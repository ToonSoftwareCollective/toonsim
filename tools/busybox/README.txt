busybox.exe - the shell toonsim runs the apps' own scripts in (tools/tsc.py: postnl, external-<app>)

This is busybox-w32, the Windows build of BusyBox - the same set of Unix tools the Toon itself runs -
by Ron Yorston, unchanged:

    version   BusyBox v1.38.0-FRP-6075-g169694ebd (64-bit, UTF-8)
    binary    https://frippery.org/files/busybox/busybox-w64u-FRP-6075-g169694ebd.exe
    sha256    6e263d154d8548d1eb936f65d1d8312c80df31c45974e48d6335e4dcc0f4f34c
    source    https://frippery.org/files/busybox/busybox-w32-FRP-6075-g169694ebd.tgz
    project   https://frippery.org/busybox/  and  https://github.com/rmyorston/busybox-w32

BusyBox is licensed under the GNU General Public License version 2 (GPLv2); its complete source code
for this version is at the "source" address above. toonsim only starts it as a separate program.

To use another shell instead (MSYS2's or Git for Windows' sh.exe), set TOONSIM_SH to its path; without
busybox.exe toonsim looks for those itself.
