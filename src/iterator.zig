const std = @import("std");
const rdb = @import("rocksdb");
const lib = @import("lib.zig");

const Allocator = std.mem.Allocator;

const RocksData = lib.RocksData;

pub const Direction = enum { forward, reverse };

pub const Iterator = struct {
    raw: RawIterator,
    direction: Direction,
    done: bool,

    const Self = @This();

    pub fn next(
        self: *Self,
        err_str: *?RocksData,
    ) error{RocksDBIterator}!?[2]RocksData {
        return self.nextGeneric([2]RocksData, RawIterator.entry, err_str);
    }

    pub fn nextKey(
        self: *Self,
        err_str: *?RocksData,
    ) error{RocksDBIterator}!?RocksData {
        return self.nextGeneric(RocksData, RawIterator.key, err_str);
    }

    pub fn nextValue(
        self: *Self,
        err_str: *?RocksData,
    ) error{RocksDBIterator}!?RocksData {
        return self.nextGeneric(RocksData, RawIterator.value, err_str);
    }

    fn nextGeneric(
        self: *Self,
        comptime T: type,
        getNext: fn (RawIterator) ?T,
        err_str: *?RocksData,
    ) error{RocksDBIterator}!?T {
        if (self.done) {
            return null;
        } else if (getNext(self.raw)) |item| {
            switch (self.direction) {
                .forward => self.raw.next(),
                .reverse => self.raw.prev(),
            }
            return item;
        } else {
            self.done = true;
            try self.raw.status(err_str);
            return null;
        }
    }
};

pub const RawIterator = struct {
    inner: *rdb.rocksdb_iterator_t,

    const Self = @This();

    pub fn seek(self: Self, key_: []const u8) void {
        rdb.rocksdb_iter_seek(self.inner, @ptrCast(key_.ptr), key_.len);
    }

    pub fn seekToFirst(self: Self) void {
        rdb.rocksdb_iter_seek_to_first(self.inner);
    }

    pub fn seekToLast(self: Self) void {
        rdb.rocksdb_iter_seek_to_last(self.inner);
    }

    pub fn valid(self: Self) bool {
        return rdb.rocksdb_iter_valid(self.inner) != 0;
    }

    pub fn entry(self: Self) ?[2]RocksData {
        if (self.valid()) {
            return .{ self.keyImpl(), self.valueImpl() };
        } else {
            return null;
        }
    }

    pub fn key(self: Self) ?RocksData {
        if (self.valid()) {
            return self.keyImpl();
        } else {
            return null;
        }
    }

    pub fn value(self: Self) ?RocksData {
        if (self.valid()) {
            return self.valueImpl();
        } else {
            return null;
        }
    }

    fn keyImpl(self: Self) RocksData {
        var len: usize = undefined;
        const ret = rdb.rocksdb_iter_key(self.inner, &len);
        return .{ .data = ret[0..len] };
    }

    fn valueImpl(self: Self) RocksData {
        var len: usize = undefined;
        const ret = rdb.rocksdb_iter_value(self.inner, &len);
        return .{ .data = ret[0..len] };
    }

    pub fn next(self: Self) void {
        rdb.rocksdb_iter_next(self.inner);
    }

    pub fn prev(self: Self) void {
        rdb.rocksdb_iter_prev(self.inner);
    }

    pub fn status(self: Self, err_str: *?RocksData) error{RocksDBIterator}!void {
        var err_str_in: ?[*:0]u8 = null;
        rdb.rocksdb_iter_get_error(self.inner, @ptrCast(&err_str_in));
        if (err_str_in) |s| {
            err_str.* = .{ .data = std.mem.span(s) };
            return error.RocksDBIterator;
        }
    }
};
