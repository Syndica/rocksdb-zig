const std = @import("std");
const rdb = @import("rocksdb");
const lib = @import("lib.zig");

const Allocator = std.mem.Allocator;

const Data = lib.Data;

const general_freer = lib.data.general_freer;

pub const Direction = enum { forward, reverse };

pub const Iterator = struct {
    raw: RawIterator,
    direction: Direction,
    done: bool,
    is_first: bool = true,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.raw.deinit();
    }

    pub fn next(self: *Self, err_str: *?Data) error{RocksDBIterator}!?[2]Data {
        return self.nextGeneric([2]Data, RawIterator.entry, err_str);
    }

    pub fn nextKey(self: *Self, err_str: *?Data) error{RocksDBIterator}!?Data {
        return self.nextGeneric(Data, RawIterator.key, err_str);
    }

    pub fn nextValue(self: *Self, err_str: *?Data) error{RocksDBIterator}!?Data {
        return self.nextGeneric(Data, RawIterator.value, err_str);
    }

    fn nextGeneric(
        self: *Self,
        comptime T: type,
        getNext: fn (RawIterator) ?T,
        err_str: *?Data,
    ) error{RocksDBIterator}!?T {
        if (self.done) {
            return null;
        } else {
            // NOTE: we call next before getting the value (instead of after)
            // because rocksdb uses pointers
            if (!self.is_first) {
                switch (self.direction) {
                    .forward => self.raw.next(),
                    .reverse => self.raw.prev(),
                }
            }

            if (getNext(self.raw)) |item| {
                self.is_first = false;
                return item;
            } else {
                self.done = true;
                try self.raw.status(err_str);
                return null;
            }
        }
    }
};

pub const RawIterator = struct {
    inner: *rdb.rocksdb_iterator_t,

    const Self = @This();

    pub fn deinit(self: Self) void {
        rdb.rocksdb_iter_destroy(self.inner);
    }

    pub fn seek(self: Self, key_: []const u8) void {
        rdb.rocksdb_iter_seek(self.inner, @ptrCast(key_.ptr), key_.len);
    }

    pub fn seekForPrev(self: Self, key_: []const u8) void {
        rdb.rocksdb_iter_seek_for_prev(self.inner, @ptrCast(key_.ptr), key_.len);
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

    pub fn entry(self: Self) ?[2]Data {
        if (self.valid()) {
            return .{ self.keyImpl(), self.valueImpl() };
        } else {
            return null;
        }
    }

    pub fn key(self: Self) ?Data {
        if (self.valid()) {
            return self.keyImpl();
        } else {
            return null;
        }
    }

    pub fn value(self: Self) ?Data {
        if (self.valid()) {
            return self.valueImpl();
        } else {
            return null;
        }
    }

    fn keyImpl(self: Self) Data {
        var len: usize = undefined;
        const ret = rdb.rocksdb_iter_key(self.inner, &len);
        return .{
            .data = ret[0..len],
            .allocator = general_freer,
        };
    }

    fn valueImpl(self: Self) Data {
        var len: usize = undefined;
        const ret = rdb.rocksdb_iter_value(self.inner, &len);
        return .{
            .data = ret[0..len],
            .allocator = general_freer,
        };
    }

    pub fn next(self: Self) void {
        rdb.rocksdb_iter_next(self.inner);
    }

    pub fn prev(self: Self) void {
        rdb.rocksdb_iter_prev(self.inner);
    }

    pub fn status(self: Self, err_str: *?Data) error{RocksDBIterator}!void {
        var err_str_in: ?[*:0]u8 = null;
        rdb.rocksdb_iter_get_error(self.inner, @ptrCast(&err_str_in));
        if (err_str_in) |s| {
            err_str.* = .{
                .data = std.mem.span(s),
                .allocator = general_freer,
            };
            return error.RocksDBIterator;
        }
    }
};
