const std = @import("std");
const rdb = @import("rocksdb");

const Allocator = std.mem.Allocator;

/// data that was allocated by rocksdb and must be freed by rocksdb
pub const Data = struct {
    allocator: Allocator,
    data: []const u8,

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
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

pub fn copy(allocator: Allocator, in: [*c]const u8) Allocator.Error![]u8 {
    return copyLen(allocator, in, std.mem.len(in));
}

pub fn copyLen(allocator: Allocator, in: [*c]const u8, len: usize) Allocator.Error![]u8 {
    const ret = try allocator.dupe(u8, in[0..len]);
    return ret;
}

pub const general_freer = Freer(rdb.rocksdb_free).allocator();
pub const pinnable_freer = Freer(rdb.rocksdb_pinnableslice_destroy).allocator();

/// Custom allocator that can be used to free memory allocated by rocksdb
fn Freer(comptime free_fn: fn (?*anyopaque) callconv(.C) void) type {
    return struct {
        pub fn allocator() Allocator {
            return Allocator{
                .ptr = undefined,
                .vtable = &vtable,
            };
        }

        const vtable = .{
            .alloc = &@This().alloc,
            .resize = &@This().resize,
            .free = &@This().free,
        };

        fn alloc(_: *anyopaque, _: usize, _: u8, _: usize) ?[*]u8 {
            return null;
        }

        fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
            return false;
        }

        fn free(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
            free_fn(@ptrCast(buf.ptr));
        }
    };
}
