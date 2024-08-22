Build and use RocksDB in zig.

# Build Dependencies

`rocksdb-zig` is pinned to [Zig `0.13`](https://ziglang.org/download/), so you will need to have it installed.

# Usage

Supported use cases:
- [⬇️](#build-rocksdb) Build a RocksDB static library using the zig build system.
- [⬇️](#import-rocksdb-c-api-in-a-zig-project) Use the RocksDB C API through auto-generated Zig bindings.
- [⬇️](#import-the-zig-bindings-library) Import an idiomatic zig library of bindings that wrap the RocksDB library with hand-written zig code.

## Build RocksDB
Clone this repository, then run `zig build`. 

You will find a statically linked `rocksdb` archive
in `zig-out/lib/librocksdb.a`.

You can use this with any language or build system.

## Import RocksDB C API in the Zig Build System.

Fetch `rocksdb` and save it to your `build.zig.zon`:
```
$ zig fetch --save=rocksdb https://github.com/Syndica/rocksdb-zig/archive/<COMMIT_HASH>.tar.gz
```

Add the import to a module:
```zig
const rocksdb = b.dependency("rocksdb", .{}).module("rocksdb");
exe.root_module.addImport("rocksdb", rocksdb);
```

Import the `rocksdb` module.
```zig
const rocksdb = @import("rocksdb");
```

## Import the Zig bindings library using the Zig Build System.

Fetch `rocksdb` and save it to your `build.zig.zon`:
```
$ zig fetch --save=rocksdb https://github.com/Syndica/rocksdb-zig/archive/<COMMIT_HASH>.tar.gz
```

Add the import to a module:
```zig
const rocksdb_bindings = b.dependency("rocksdb", .{}).module("rocksdb-bindings");
exe.root_module.addImport("rocksdb-bindings", rocksdb_bindings);
```

Import the `rocksdb-bindings` module.
```zig
const rocksdb = @import("rocksdb-bindings");
```
