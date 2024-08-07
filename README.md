Build and use RocksDB in zig.

Supported use cases:
- [⬇️](#build-rocksdb) Build a RocksDB static library using the zig build system.
- [⬇️](#import-rocksdb-c-api-in-a-zig-project) Import RocksDB's C API as a normal zig dependency in a zig project.
- [⬇️](#import-the-zig-bindings-library) Import an idiomatic zig library of bindings that wrap the RocksDB library with hand-written zig code.

In all cases, RocksDB and all of its dependencies are statically linked. This offers portability because it works without needing to dynamically link to any shared libraries in the system.

# Usage

## Build RocksDB
Clone this repository, then run `zig build`. The `zig-out` directory will contain the following:
- include: folder containing all rocksdb header files
- lib/librocksdb.a: statically linkable rocksdb binary containing all rocksdb dependencies.

You can use these artifacts with any language or build system.

## Import RocksDB C API in a Zig project

Add this to your dependencies in build.zig.zon:
```zig
.rocksdb = .{
    .url = "https://github.com/Syndica/rocksdb-zig/archive/<COMMIT_HASH>.tar.gz",
    .hash = "<TARBALL_HASH>",
},
```

Add this to your build.zig:
```zig
const rocksdb = b.dependency("rocksdb", .{}).module("rocksdb");
exe.root_module.addImport("rocksdb", rocksdb);
```

Add this to your zig program:
```zig
const rocksdb = @import("rocksdb");
```

## Import the Zig bindings library

Add this to your dependencies in build.zig.zon:
```zig
.rocksdb = .{
    .url = "https://github.com/Syndica/rocksdb-zig/archive/<COMMIT_HASH>.tar.gz",
    .hash = "<TARBALL_HASH>",
},
```

Add this to your build.zig:
```zig
const rocksdb_bindings = b.dependency("rocksdb", .{}).module("rocksdb-bindings");
exe.root_module.addImport("rocksdb-bindings", rocksdb_bindings);
```

Add this to your zig program:
```zig
const rocksdb = @import("rocksdb-bindings");
```

# Build Dependencies
must be in PATH:
- make
- zig

Currently this works by having Zig call out to the RocksDB build system under the hood. In the future, I'd like to replace this with zig as the entire build system. For now, you'll need make installed. This configures make to use zig as the c and c++ compiler, so you don't need any other c compiler installed, but this is why you do need zig in your PATH.
