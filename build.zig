const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run bindings tests");

    // rocksdb itself as a zig module
    const rocksdb_mod = buildRocksDb(b, target, optimize);

    // zig bindings library to rocksdb
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
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

/// Create a zig module for the bare C++ library by exposing its C api.
/// Builds rocksdb, links it, and translates its headers.
///
/// TODO: remove make dependency by reimplementing in zig
fn buildRocksDb(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
) *Build.Module {
    const rocks_dep = b.dependency("rocksdb", .{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = rocks_dep.path("include/rocksdb/c.h"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("rocksdb", .{
        .root_source_file = translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    const make_and_move = b.addExecutable(.{
        .name = "make_and_move.zig",
        .root_source_file = b.path("scripts/make_and_move.zig"),
        .target = b.resolveTargetQuery(.{}),
    });
    const rocks_path = rocks_dep.path("");
    const librocksdb_a = addMakeAndMove(b, make_and_move, rocks_path, "static_lib", "librocksdb.a");
    const libbz2_a = addMakeAndMove(b, make_and_move, rocks_path, "libbz2.a", "libbz2.a");
    const libz_a = addMakeAndMove(b, make_and_move, rocks_path, "libz.a", "libz.a");

    mod.addIncludePath(rocks_dep.path("include"));

    mod.addObjectFile(librocksdb_a);
    mod.addObjectFile(libbz2_a);
    mod.addObjectFile(libz_a);

    return mod;
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
