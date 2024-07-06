const std = @import("std");
const rdb = @import("rocksdb");

const Allocator = std.mem.Allocator;

/// data that was allocated by rocksdb and must be freed by rocksdb
pub const Data = struct {
    data: []const u8,

    pub fn deinit(self: @This()) void {
        free(self.data.ptr);
    }

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try std.fmt.formatBuf(self.data, options, writer);
    }
};

/// Free memory that was allocated by rocksdb.
///
/// Typically, you would only use this if you unwrap a
/// slice out of the Data struct, and discard the Data
/// struct before freeing the memory.
pub fn free(bytes: []const u8) void {
    rdb.rocksdb_free(@constCast(@ptrCast(bytes.ptr)));
}

pub fn copy(allocator: Allocator, in: [*c]const u8) Allocator.Error![]u8 {
    return copyLen(allocator, in, std.mem.len(in));
}

pub fn copyLen(allocator: Allocator, in: [*c]const u8, len: usize) Allocator.Error![]u8 {
    const ret = try allocator.alloc(u8, len);
    @memcpy(ret, in[0..len]);
    return ret;
}
