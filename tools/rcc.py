"""Reads Qt binary resource files (.rcc), such as the Toon's resources-static-base.rcc.

    python rcc.py list  FILE.rcc [PREFIX]        list the files (optionally under PREFIX)
    python rcc.py cat   FILE.rcc PATH            print one file (e.g. apps/thermostat/ThermostatApp.qml)
    python rcc.py extract FILE.rcc OUTDIR        write every file below OUTDIR

Format (qtbase/src/corelib/io/qresource.cpp): header 'qres', version, tree/data/names offsets; tree
nodes of 14 bytes (v1) or 22 bytes (v2+, with a modification time); zlib-compressed entries carry the
qCompress 4-byte length prefix.
"""
import os, struct, sys, zlib

class Rcc:
    def __init__(self, path):
        self.buf = open(path, "rb").read()
        if self.buf[:4] != b"qres":
            raise ValueError(path + " is not a Qt resource file")
        self.version, self.tree, self.data, self.names = struct.unpack(">IIII", self.buf[4:20])
        self.node_size = 14 if self.version == 1 else 22

    def _name(self, off):
        p = self.names + off
        length = struct.unpack(">H", self.buf[p:p + 2])[0]
        return self.buf[p + 6:p + 6 + length * 2].decode("utf-16-be")

    def _node(self, i):
        p = self.tree + i * self.node_size
        name_off, flags = struct.unpack(">IH", self.buf[p:p + 6])
        if flags & 2:                      # directory
            count, first = struct.unpack(">II", self.buf[p + 6:p + 14])
            return name_off, flags, ("dir", count, first)
        data_off = struct.unpack(">I", self.buf[p + 10:p + 14])[0]
        return name_off, flags, ("file", data_off)

    def _content(self, flags, data_off):
        p = self.data + data_off
        size = struct.unpack(">I", self.buf[p:p + 4])[0]
        raw = self.buf[p + 4:p + 4 + size]
        if flags & 1:                      # zlib (qCompress: 4-byte uncompressed length first)
            return zlib.decompress(raw[4:])
        if flags & 4:
            raise NotImplementedError("zstd-compressed resource")
        return raw

    def walk(self, i=0, prefix=""):
        name_off, flags, kind = self._node(i)
        if kind[0] == "dir":
            for c in range(kind[2], kind[2] + kind[1]):
                cname = self._name(self._node(c)[0])
                yield from self.walk(c, prefix + cname + "/" if self._node(c)[2][0] == "dir" else prefix + cname)
        else:
            yield prefix, lambda f=flags, d=kind[1]: self._content(f, d)

    def files(self):
        return {path: getter for path, getter in self.walk()}


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    r = Rcc(path)
    files = r.files()
    if cmd == "list":
        pre = sys.argv[3] if len(sys.argv) > 3 else ""
        for p in sorted(files):
            if p.startswith(pre): print(p)
    elif cmd == "cat":
        sys.stdout.buffer.write(files[sys.argv[3]]())
    elif cmd == "extract":
        out = sys.argv[3]
        for p, get in files.items():
            dest = os.path.join(out, *p.split("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f: f.write(get())
        print("extracted", len(files), "files to", out)

if __name__ == "__main__":
    main()
