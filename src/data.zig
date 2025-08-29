const std = @import("std");
const rdb = @import("rocksdb");

const Allocator = std.mem.Allocator;

/// data that was allocated by rocksdb and must be freed by rocksdb
pub const Data = struct {
    data: []const u8,
    free: *const fn (?*anyopaque) callconv(.c) void,

    pub fn deinit(self: Data) void {
        self.free(@ptrCast(@constCast(self.data.ptr)));
    }

    pub fn format(self: Data, writer: *std.io.Writer) !void {
        try writer.print("{any}", .{self});
    }
};

pub fn copy(allocator: Allocator, in: [*c]const u8) Allocator.Error![]u8 {
    return copyLen(allocator, in, std.mem.len(in));
}

pub fn copyLen(allocator: Allocator, in: [*c]const u8, len: usize) Allocator.Error![]u8 {
    const ret = try allocator.dupe(u8, in[0..len]);
    return ret;
}
