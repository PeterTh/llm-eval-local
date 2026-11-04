"""GDB-only observer of unchanged result-output functions, not a program patch.

ABI scope: x86-64 System V, libstdc++ vector<T>, exact un-cloned template entries.
Memory is read, never written. Hardware execution breakpoints leave code bytes
unchanged. Large array payloads are temporary local files, not publication data.
"""
import hashlib
import json
import os
import struct

import gdb


output_dir = os.environ["VALIDATION_ARRAY_DIR"]
config_path = os.environ["VALIDATION_ARRAY_CONFIG"]
with open(config_path, encoding="utf-8") as stream:
    config = json.load(stream)
if not os.path.realpath(output_dir).startswith("/tmp/"):
    raise RuntimeError("Array captures must stay under /tmp")
os.mkdir(output_dir)
captures = []
errors = []
exits = []
max_bytes = 64 * 1024 * 1024


def c_string(inferior, address):
    # Small bounded reads also work at a mapped-page boundary.
    value = bytearray()
    for offset in range(256):
        byte = bytes(inferior.read_memory(address + offset, 1))
        if byte == b"\0":
            return value.decode("utf-8", errors="strict")
        value.extend(byte)
    raise RuntimeError("Result name lacks a bounded NUL terminator")


class ArrayBoundary(gdb.Breakpoint):
    def __init__(self, symbol, dtype, width):
        super().__init__("*" + symbol, type=gdb.BP_HARDWARE_BREAKPOINT,
                         internal=True)
        self.symbol = symbol
        self.dtype = dtype
        self.width = width
        self.silent = True

    def stop(self):
        try:
            inferior = gdb.selected_inferior()
            if inferior.architecture().name() != "i386:x86-64":
                raise RuntimeError("Unsupported result ABI")
            frame = gdb.newest_frame()
            vector_address = int(frame.read_register("rdi"))
            name_address = int(frame.read_register("rsi"))
            start, finish, capacity = struct.unpack(
                "<QQQ", bytes(inferior.read_memory(vector_address, 24)))
            length = finish - start
            if not (start <= finish <= capacity and 0 <= length <= max_bytes
                    and length % self.width == 0):
                raise RuntimeError("Invalid or oversized vector bounds")
            name = c_string(inferior, name_address)
            filename = "array-%04d.%s" % (len(captures), self.dtype)
            digest = hashlib.sha256()
            with open(os.path.join(output_dir, filename), "xb") as stream:
                for offset in range(0, length, 1024 * 1024):
                    data = bytes(inferior.read_memory(
                        start + offset, min(1024 * 1024, length - offset)))
                    digest.update(data)
                    stream.write(data)
            captures.append({"name": name, "dtype": self.dtype,
                             "elements": length // self.width, "bytes": length,
                             "file": filename, "sha256": digest.hexdigest(),
                             "symbol": self.symbol})
            return False
        except Exception as error:
            errors.append(type(error).__name__ + ": " + str(error))
            return True


def exited(event):
    exits.append(getattr(event, "exit_code", None))


gdb.events.exited.connect(exited)
for command in ["set pagination off", "set confirm off",
                "set print thread-events off", "set disable-randomization off",
                "set startup-with-shell off", "maintenance set worker-threads 1",
                "unset environment VALIDATION_ARRAY_DIR",
                "unset environment VALIDATION_ARRAY_CONFIG"]:
    gdb.execute(command, to_string=True)

allowed = {
    "_Z13print_resultsIdEvRKSt6vectorIT_SaIS1_EEPKc": ("f64le", 8),
    "_Z13print_resultsIfEvRKSt6vectorIT_SaIS1_EEPKc": ("f32le", 4),
    "_Z17print_results_intIjEvRKSt6vectorIT_SaIS1_EEPKc": ("u32le", 4),
    "_Z17print_results_intIiEvRKSt6vectorIT_SaIS1_EEPKc": ("i32le", 4),
}
try:
    symbols = config["symbols"]
    if not symbols or len(symbols) != len(set(symbols)) or len(symbols) > 4:
        raise RuntimeError("Unsupported result-boundary symbol set")
    breakpoints = [ArrayBoundary(symbol, *allowed[symbol]) for symbol in symbols]
    if any(point.pending for point in breakpoints):
        raise RuntimeError("Unresolved result boundary")
    gdb.execute("run", to_string=False)
    if not exits:
        errors.append("Inferior stopped before normal exit")
except Exception as error:
    errors.append(type(error).__name__ + ": " + str(error))

with open(os.path.join(output_dir, "capture.json"), "x", encoding="utf-8") as stream:
    json.dump({"schema_version": 1, "gdb_version": gdb.VERSION,
               "mechanism": "hardware entry breakpoint and read-only memory capture",
               "captures": captures, "errors": errors, "exit_codes": exits},
              stream, indent=2)
    stream.write("\n")
if errors or exits != [0]:
    gdb.execute("quit 86")
