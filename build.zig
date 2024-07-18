const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) void {
    const target: ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: OptimizeMode = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run bindings tests");

    const rocks_dep = b.dependency("rocksdb", .{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = rocks_dep.path("include/rocksdb/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const rocksdb_mod = b.addModule("rocksdb", .{
        .root_source_file = translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    buildAndLinkRocksDb(b, rocksdb_mod);

    // module
    const bindings_mod = b.addModule("rocksdb-bindings", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });
    bindings_mod.addImport("rocksdb", rocksdb_mod);

    // tests
    const tests = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib.zig"),
    });
    tests.root_module.addImport("rocksdb", rocksdb_mod);
    buildAndLinkRocksDb(b, &tests.root_module);

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}

/// Build and link the C++ library.
fn buildAndLinkRocksDb(
    b: *Build,
    /// Module to add the object files to.
    mod: *Build.Module,
) void {
    const make_and_move_exe = makeAndMoveExe(b);

    // build rocksdb with make
    // TODO: remove make dependency by reimplementing in zig
    const rocks_dep = b.dependency("rocksdb", .{});
    const rocks_path = rocks_dep.path("");

    const librocksdb_a = addMakeAndMove(b, make_and_move_exe, rocks_path, "static_lib", "librocksdb.a");
    const libbz2_a = addMakeAndMove(b, make_and_move_exe, rocks_path, "libbz2.a", "libbz2.a");
    const libz_a = addMakeAndMove(b, make_and_move_exe, rocks_path, "libz.a", "libz.a");

    mod.addIncludePath(rocks_dep.path("include"));

    mod.addObjectFile(librocksdb_a);
    mod.addObjectFile(libbz2_a);
    mod.addObjectFile(libz_a);

    mod.linkSystemLibrary("zstd", .{});
    mod.linkSystemLibrary("lz4", .{});
    mod.linkSystemLibrary("snappy", .{});
    mod.linkSystemLibrary("uring", .{});
}

fn makeAndMoveExe(b: *Build) *Build.Step.Compile {
    return b.addExecutable(.{
        .name = "make-and-move",
        .root_source_file = b.path("scripts/make_and_move.zig"),
        .target = b.resolveTargetQuery(.{}),
    });
}

/// add a build step to make the library and then move the output file to the cache
/// the purpose is to have the zig caching system track the output file
fn addMakeAndMove(
    b: *Build,
    make_and_move_exe: *Build.Step.Compile,
    rocks_lp: Build.LazyPath,
    make_rule: []const u8,
    filename: []const u8,
) Build.LazyPath {
    const run = b.addRunArtifact(make_and_move_exe);
    run.setEnvironmentVariable("DEBUG_LEVEL", if (b.verbose) "1" else "0");

    run.addDirectoryArg(rocks_lp);
    run.addArg(make_rule);
    run.addArg(filename);
    if (b.verbose) {
        run.stdio = .inherit;
    }

    return run.addOutputFileArg(filename);
}
