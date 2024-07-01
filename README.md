Build and use RocksDB in zig.

Supported use cases:
- [⬇️](#build-rocksdb) Build a RocksDB static library using the zig build system.
- [⬇️](#directly-use-rocksdb-in-a-zig-project) Directly import RocksDB as a normal zig dependency in a zig project.
- [⬇️](#use-the-zig-bindings-library) Use an idiomatic zig library of bindings that wrap the RocksDB library with hand-written zig code.

In all cases, RocksDB and all of its dependencies are statically linked. This offers portability because it works without needing to dynamically link to any shared libraries in the system.

# Usage

## Build RocksDB
Clone this repository, then run `zig build`. The `zig-out` directory will contain the following:
- include: folder containing all rocksdb header files
- lib/librocksdb.a: statically linkable rocksdb binary containing all rocksdb dependencies.

You can use these artifacts with any language or build system.

## Directly use RocksDB in a Zig project

Add this to your dependencies in build.zig.zon:
```zig
.rocksdb = .{
    .url = "https://github.com/Syndica/rocksdb-zig/archive/refs/tags/v9.2.1-1.tar.gz",
    .hash = "TODO",
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

## Use the Zig Bindings Library

Add this to your dependencies in build.zig.zon:
```zig
.rocksdb = .{
    .url = "https://github.com/Syndica/rocksdb-zig/archive/refs/tags/v9.2.1-1.tar.gz",
    .hash = "TODO",
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
