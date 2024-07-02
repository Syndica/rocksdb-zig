const std = @import("std");
const rdb = @import("rocksdb");

const Allocator = std.mem.Allocator;

pub const WriteBatch = struct {
    inner: *rdb.rocksdb_writebatch_t,

    pub fn init() WriteBatch {
        return .{ .inner = rdb.rocksdb_writebatch_create().? };
    }

    pub fn deinit(self: WriteBatch) void {
        rdb.rocksdb_free(self.inner);
    }
};
