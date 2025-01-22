const std = @import("std");
const rdb = @import("rocksdb");
const lib = @import("lib.zig");

const Allocator = std.mem.Allocator;

const ColumnFamilyHandle = lib.ColumnFamilyHandle;

pub const WriteBatch = struct {
    inner: *rdb.rocksdb_writebatch_t,

    const Self = @This();

    pub fn init() WriteBatch {
        return .{ .inner = rdb.rocksdb_writebatch_create().? };
    }

    pub fn deinit(self: WriteBatch) void {
        rdb.rocksdb_writebatch_destroy(self.inner);
    }

    pub fn put(
        self: *const Self,
        column_family: ColumnFamilyHandle,
        key: []const u8,
        value: []const u8,
    ) void {
        rdb.rocksdb_writebatch_put_cf(
            self.inner,
            column_family,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
        );
    }

    pub fn delete(
        self: *const Self,
        column_family: ColumnFamilyHandle,
        key: []const u8,
    ) void {
        rdb.rocksdb_writebatch_delete_cf(
            self.inner,
            column_family,
            key.ptr,
            key.len,
        );
    }

    pub fn deleteRange(
        self: *const Self,
        column_family: ColumnFamilyHandle,
        start_key: []const u8,
        end_key: []const u8,
    ) void {
        rdb.rocksdb_writebatch_delete_range_cf(
            self.inner,
            column_family,
            start_key.ptr,
            start_key.len,
            end_key.ptr,
            end_key.len,
        );
    }
};
