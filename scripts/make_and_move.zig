const std = @import("std");

pub fn main() !void {
    if (std.os.argv.len == 5) try makeAndMove(
        std.heap.page_allocator,
        std.mem.span(std.os.argv[1]),
        std.mem.span(std.os.argv[2]),
        std.mem.span(std.os.argv[3]),
        std.mem.span(std.os.argv[4]),
    ) else std.debug.print(
        \\
        \\Run make, and move the output file to a new location.
        \\
        \\USAGE:
        \\
        \\     make_and_move [MAKEFILE_DIR] [MAKE_RULE] [ARTIFACT_PATH] [TARGET_PATH]
        \\
        \\  MAKEFILE_DIR   Directory containing the Makefile
        \\  MAKE_RULE      Rule to run, as in `make [MAKE_RULE]`
        \\  ARTIFACT_PATH  Path of the file created by make (relative to MAKEFILE_DIR)
        \\  TARGET_PATH    Desired target location to move the output file
        \\
        \\
    , .{});
}

fn makeAndMove(
    allocator: std.mem.Allocator,
    makefile_dir: []const u8,
    make_rule: []const u8,
    artifact_path: []const u8,
    target_path: []const u8,
) !void {
    var buf: [4]u8 = undefined;
    const cpu_count = try std.fmt.bufPrint(&buf, "{}", .{try std.Thread.getCpuCount()});
    var make = std.process.Child.init(
        &.{ "make", "CC=zig cc", "CXX=zig c++", "-C", makefile_dir, make_rule, "-j", cpu_count },
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
    const source_path = try std.fs.path.join(allocator, &.{ makefile_dir, artifact_path });
    try std.fs.renameAbsolute(source_path, target_path);
}
