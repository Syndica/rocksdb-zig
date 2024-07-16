const std = @import("std");

const ResolvedTarget = std.Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    const target: ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: OptimizeMode = b.standardOptimizeOption(.{});

    const lib = buildRocksDb(b, target, optimize);
    const mod = exposeRocksDb(b, target, optimize, lib);
    buildRocksDbBindings(b, target, optimize, mod);
}

/// Build the C++ library
pub fn buildRocksDb(
    b: *std.Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
) *std.Build.Step.Compile {
    // build rocksdb with make
    // TODO: remove make dependency by reimplementing in zig
    const rocks_dep = b.dependency("rocksdb", .{});
    const rocks_path = rocks_dep.path("").getPath(b);
    const build_rocks, const librocksdb_a = addMakeAndMove(b, rocks_path, "static_lib", "librocksdb.a");
    const build_bz2, const libbz2_a = addMakeAndMove(b, rocks_path, "libbz2.a", "libbz2.a");
    const build_z, const libz_a = addMakeAndMove(b, rocks_path, "libz.a", "libz.a");
    const DEBUG_LEVEL = switch (optimize) {
        .Debug => "1",
        else => "0",
    };
    build_rocks.setEnvironmentVariable("DEBUG_LEVEL", DEBUG_LEVEL);
    build_bz2.setEnvironmentVariable("DEBUG_LEVEL", DEBUG_LEVEL);
    build_z.setEnvironmentVariable("DEBUG_LEVEL", DEBUG_LEVEL);

    // create static library
    const lib = b.addStaticLibrary(.{
        .name = "rocksdb",
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibCpp();
    lib.installHeadersDirectory(rocks_dep.path("include"), "", .{});

    lib.step.dependOn(&build_rocks.step);
    lib.step.dependOn(&build_bz2.step);
    lib.step.dependOn(&build_z.step);

    lib.addObjectFile(librocksdb_a);
    lib.addObjectFile(libbz2_a);
    lib.addObjectFile(libz_a);

    b.installArtifact(lib);

    return lib;
}

/// Directly expose the C++ library as a zig module
pub fn exposeRocksDb(
    b: *std.Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    lib: *std.Build.Step.Compile,
) *std.Build.Module {
    const rocks_dep = b.dependency("rocksdb", .{});
    const translate_c = b.addTranslateC(.{
        .root_source_file = rocks_dep.path("include/rocksdb/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    translate_c.addIncludeDir(rocks_dep.path("include").getPath(b));
    const mod = translate_c.addModule("rocksdb");
    mod.link_libcpp = true;
    mod.linkLibrary(lib);

    return mod;
}

/// Build the zig bindings library, which is a wrapper for the C++ library
pub fn buildRocksDbBindings(
    b: *std.Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    rocksdb: *std.Build.Module,
) void {
    // module
    var bindings = b.addModule("rocksdb-bindings", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });
    bindings.addImport("rocksdb", rocksdb);

    // tests
    const tests = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });
    tests.root_module.addImport("rocksdb", rocksdb);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run bindings tests");
    test_step.dependOn(&run_tests.step);
}

/// add a build step to make the library and then move the output file to the cache
/// the purpose is to have the zig caching system track the output file
fn addMakeAndMove(
    b: *std.Build,
    rocks_path: []const u8,
    make_rule: []const u8,
    filename: []const u8,
) struct {
    *std.Build.Step.Run,
    std.Build.LazyPath,
} {
    const run = b.addSystemCommand(&.{
        "zig", "run", b.path("build.zig").getPath(b), "--", rocks_path, make_rule, filename,
    });
    const path = run.addOutputFileArg(filename);
    return .{ run, path };
}

/// this should only be called in main. the zig build system will
/// run this when the addMakeAndMove step is run.
/// directly executes the make and move
fn makeAndMove(
    allocator: std.mem.Allocator,
    rocks_path: []const u8,
    make_rule: []const u8,
    filename: []const u8,
    target_path: []const u8,
) !void {
    var buf: [4]u8 = undefined;
    const cpu_count = try std.fmt.bufPrint(&buf, "{}", .{try std.Thread.getCpuCount()});
    var make = std.process.Child.init(
        &.{ "make", "CC=zig cc", "CXX=zig c++", "-C", rocks_path, make_rule, "-j", cpu_count },
        allocator,
    );
    const term = make.spawnAndWait() catch |e| {
        switch (e) {
            error.FileNotFound => std.debug
                .print("Ensure `make` is installed and available in PATH.\n", .{}),
            else => {},
        }
        return e;
    };
    if (term.Exited != 0) {
        std.debug.print("make exited with code {}\n", .{term.Exited});
        return error.MakeError;
    }
    const source_path = try std.fs.path.join(allocator, &.{ rocks_path, filename });
    try std.fs.renameAbsolute(source_path, target_path);
}

pub fn main() !void {
    try makeAndMove(
        std.heap.page_allocator,
        std.mem.span(std.os.argv[1]),
        std.mem.span(std.os.argv[2]),
        std.mem.span(std.os.argv[3]),
        std.mem.span(std.os.argv[4]),
    );
}
