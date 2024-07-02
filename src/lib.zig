const std = @import("std");
const rdb = @import("rocksdb");

const Allocator = std.mem.Allocator;

pub const RocksDB = struct {
    allocator: Allocator,
    db: *rdb.rocksdb_t,
    column_families: std.StringHashMap(*rdb.rocksdb_column_family_handle_t),

    const Self = @This();

    pub fn open(dir: []const u8, err_str: *?RocksData) error{RocksDBOpen}!Self {
        const options = rdb.rocksdb_options_create();
        rdb.rocksdb_options_set_create_if_missing(options, 1); // TODO is null actually replaced?
        var ch = CallHandler.init(err_str);
        const db = try ch.handle(
            rdb.rocksdb_open(options, dir.ptr, &ch.err_str_in),
            error.RocksDBOpen,
        );
        return .{ .db = db.? };
    }

    pub fn openCf(
        allocator: Allocator,
        dir: []const u8,
        db_options: DBOptions,
        column_families: []const ColumnFamilyDescription,
        err_str: *?RocksData,
    ) (Allocator.Error || error{RocksDBOpen})!struct { Self, []const ColumnFamily } {
        const cf_options = try allocator.alloc(?*const rdb.rocksdb_options_t, column_families.len);
        defer allocator.free(cf_options);
        const cf_names = try allocator.alloc([*c]const u8, column_families.len);
        defer allocator.free(cf_names);
        for (column_families, 0..) |cf, i| {
            cf_names[i] = @ptrCast(cf.name.ptr);
            cf_options[i] = cf.options.convert();
        }
        const cf_handles = try allocator.alloc(?*rdb.rocksdb_column_family_handle_t, column_families.len);
        defer allocator.free(cf_handles);
        var ch = CallHandler.init(err_str);
        const db = try ch.handle(rdb.rocksdb_open_column_families(
            db_options.convert(),
            dir.ptr,
            @intCast(cf_names.len),
            @ptrCast(cf_names.ptr),
            @ptrCast(cf_options.ptr),
            @ptrCast(cf_handles.ptr),
            &ch.err_str_in,
        ), error.RocksDBOpen);
        const cfs = try allocator.alloc(ColumnFamily, column_families.len);
        var cf_map = std.StringHashMap(*rdb.rocksdb_column_family_handle_t).init(allocator);
        for (cfs, 0..) |*cf, i| {
            const name = try allocator.alloc(u8, column_families[i].name.len);
            @memcpy(name, column_families[i].name);
            cf.* = .{
                .name = name,
                .handle = cf_handles[i].?,
            };
            try cf_map.put(name, cf_handles[i].?);
        }
        const self = Self{
            .allocator = allocator,
            .db = db.?,
            .column_families = cf_map,
        };

        return .{ self, cfs };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.column_families.keyIterator();
        while (iter.next()) |k| {
            self.allocator.free(k.*);
        }
        self.column_families.deinit();
        rdb.rocksdb_close(self.db);
    }

    pub fn createColumnFamily(
        self: *Self,
        name: []const u8,
        err_str: *?RocksData,
    ) !*rdb.rocksdb_column_family_handle_t {
        const options = rdb.rocksdb_options_create();
        var ch = CallHandler.init(err_str);
        return (try ch.handle(rdb.rocksdb_create_column_family(
            self.db,
            options,
            @as([*c]const u8, @ptrCast(name)),
            &ch.err_str_in,
        ), error.RocksDBCreateColumnFamily)).?;
    }

    pub fn columnFamily(self: *const Self, cf_name: []const u8) ?*rdb.rocksdb_column_family_handle_t {
        return self.column_families.get(cf_name);
    }

    pub fn put(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        value: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBPut}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_put_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &ch.err_str_in,
        ), error.RocksDBPut);
    }

    pub fn get(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBGet}!?RocksData {
        var valueLength: usize = 0;
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        const value = try ch.handle(rdb.rocksdb_get_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            &valueLength,
            &ch.err_str_in,
        ), error.RocksDBGet);

        if (value == 0) {
            return null;
        }

        return .{ .bytes = value[0..valueLength] };
    }

    pub fn delete(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBDelete}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            &ch.err_str_in,
        ), error.RocksDBDelete);
    }

    pub fn deleteFileInRange(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        start_key: []const u8,
        limit_key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBDeleteFileInRange}!void {
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_file_in_range_cf(
            self.db,
            family,
            @ptrCast(start_key.ptr),
            start_key.len,
            @ptrCast(limit_key.ptr),
            limit_key.len,
            &ch.err_str_in,
        ), error.RocksDBDeleteFileInRange);
    }

    pub fn iterator(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
    ) Iterator {
        const it = self.rawIterator(family);
        it.seekToFirst();
        return .{
            .raw = it,
            .direction = .forward,
            .done = false,
        };
    }

    pub fn rawIterator(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
    ) RawIterator {
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options); // TODO does this need to outlive the iterator?
        const inner_iter = rdb.rocksdb_create_iterator_cf(self.db, options, family).?;
        const ri = RawIterator{ .inner = inner_iter };
        return ri;
    }

    pub fn liveFiles(self: *const Self, allocator: Allocator) Allocator.Error!std.ArrayList(LiveFile) {
        const files = rdb.rocksdb_livefiles(self.db).?;
        const num_files: usize = @intCast(rdb.rocksdb_livefiles_count(files));
        var livefiles = std.ArrayList(LiveFile).init(allocator);
        var key_size: usize = 0;
        for (0..num_files) |i| {
            const file_num: c_int = @intCast(i);
            try livefiles.append(.{
                .allocator = allocator,
                .column_family_name = try copy(allocator, rdb.rocksdb_livefiles_column_family_name(files, file_num)),
                .name = try copy(allocator, rdb.rocksdb_livefiles_name(files, file_num)),
                .size = rdb.rocksdb_livefiles_size(files, file_num),
                .level = rdb.rocksdb_livefiles_level(files, file_num),
                .start_key = try copyLen(allocator, rdb.rocksdb_livefiles_smallestkey(files, file_num, &key_size), key_size),
                .end_key = try copyLen(allocator, rdb.rocksdb_livefiles_largestkey(files, file_num, &key_size), key_size),
                .num_entries = rdb.rocksdb_livefiles_entries(files, file_num),
                .num_deletions = rdb.rocksdb_livefiles_deletions(files, file_num),
            });
        }
        rdb.rocksdb_livefiles_destroy(files);
        return livefiles;
    }

    pub fn propertyValueCf(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        propname: []const u8,
    ) RocksData {
        const value = rdb.rocksdb_property_value_cf(
            self.db,
            family,
            @ptrCast(propname.ptr),
        );
        return .{ .bytes = std.mem.span(value) };
    }

    pub fn write(
        self: *const Self,
        batch: WriteBatch,
        err_str: *?RocksData,
    ) error{RocksDBWrite}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_write(
            self.db,
            options,
            batch.inner,
            &ch.err_str_in,
        ), error.RocksDBWrite);
    }
};

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
        return .{ .bytes = ret[0..len] };
    }

    fn valueImpl(self: Self) RocksData {
        var len: usize = undefined;
        const ret = rdb.rocksdb_iter_value(self.inner, &len);
        return .{ .bytes = ret[0..len] };
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
            err_str.* = .{ .bytes = std.mem.span(s) };
            return error.RocksDBIterator;
        }
    }
};

fn copy(allocator: Allocator, in: [*c]const u8) Allocator.Error![]u8 {
    return copyLen(allocator, in, std.mem.len(in));
}

fn copyLen(allocator: Allocator, in: [*c]const u8, len: usize) Allocator.Error![]u8 {
    const ret = try allocator.alloc(u8, len);
    @memcpy(ret, in[0..len]);
    return ret;
}

pub const WriteBatch = struct {
    inner: *rdb.rocksdb_writebatch_t,

    pub fn init() WriteBatch {
        return .{ .inner = rdb.rocksdb_writebatch_create().? };
    }

    pub fn deinit(self: WriteBatch) void {
        rdb.rocksdb_free(self.inner);
    }
};

/// The metadata that describes a SST file
pub const LiveFile = struct {
    allocator: Allocator,
    /// Name of the column family the file belongs to
    column_family_name: []const u8,
    /// Name of the file
    name: []const u8,
    /// Size of the file
    size: usize,
    /// Level at which this file resides
    level: i32,
    /// Smallest user defined key in the file
    start_key: ?[]const u8,
    /// Largest user defined key in the file
    end_key: ?[]const u8,
    /// Number of entries/alive keys in the file
    num_entries: u64,
    /// Number of deletions/tomb key(s) in the file
    num_deletions: u64,

    pub fn deinit(self: LiveFile) void {
        self.allocator.free(self.column_family_name);
        self.allocator.free(self.name);
        if (self.start_key) |start_key| self.allocator.free(start_key);
        if (self.end_key) |end_key| self.allocator.free(end_key);
    }
};

/// data that was allocated by rocksdb and must be freed by rocksdb
pub const RocksData = struct {
    bytes: []const u8,

    fn deinit(self: @This()) void {
        rdb.rocksdb_free(@constCast(@ptrCast(self.bytes.ptr)));
    }

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try std.fmt.formatBuf(self.bytes, options, writer);
    }
};

pub const ColumnFamilyDescription = struct {
    name: []const u8,
    options: ColumnFamilyOptions = .{},
};

pub const ColumnFamily = struct {
    name: []const u8,
    handle: *rdb.rocksdb_column_family_handle_t,
};

pub const DBOptions = struct {
    create_if_missing: bool = false,
    create_missing_column_families: bool = false,

    fn convert(do: DBOptions) *rdb.struct_rocksdb_options_t {
        const ro = rdb.rocksdb_options_create().?;
        if (do.create_if_missing) rdb.rocksdb_options_set_create_if_missing(ro, 1);
        if (do.create_missing_column_families) rdb.rocksdb_options_set_create_missing_column_families(ro, 1);
        return ro;
    }
};

pub const ColumnFamilyOptions = struct {
    fn convert(_: ColumnFamilyOptions) *rdb.struct_rocksdb_options_t {
        return rdb.rocksdb_options_create().?;
    }
};

const CallHandler = struct {
    /// The error string to pass into rocksdb.
    err_str_in: ?[*:0]u8 = null,
    /// The user's error string.
    err_str_out: *?RocksData,

    fn init(err_str_out: *?RocksData) @This() {
        return .{ .err_str_out = err_str_out };
    }

    fn errIn(self: *@This()) [*c][*c]u8 {
        return @ptrCast(&self.err_str_in);
    }

    fn handle(
        self: *@This(),
        ret: anytype,
        comptime err: anytype,
    ) @TypeOf(err)!@TypeOf(ret) {
        if (self.err_str_in) |s| {
            self.err_str_out.* = .{ .bytes = std.mem.span(s) };
            return err;
        } else {
            return ret;
        }
    }
};

test RocksDB {
    var err_str: ?RocksData = null;
    defer if (err_str) |e| e.deinit();
    runTest(&err_str) catch |e| {
        std.debug.print("{}: {?}\n", .{ e, err_str });
        return e;
    };
}

fn runTest(err_str: *?RocksData) !void {
    var db, const families = try RocksDB.openCf(
        std.testing.allocator,
        "test-state",
        .{
            .create_if_missing = true,
            .create_missing_column_families = true,
        },
        &.{
            .{ .name = "default" },
            .{ .name = "another" },
        },
        err_str,
    );
    defer db.deinit();
    defer std.testing.allocator.free(families);
    const a_family = families[1].handle;

    _ = try db.put(a_family, "hello", "world", err_str);
    _ = try db.put(a_family, "zebra", "world", err_str);
    const val = try db.get(a_family, "hello", err_str);
    try std.testing.expect(std.mem.eql(u8, val.?.bytes, "world"));

    var iter = db.iterator(a_family);
    var v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.bytes));
    v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.bytes));

    try std.testing.expect(null == try iter.next(err_str));

    try db.delete(a_family, "hello", err_str);

    const noval = try db.get(a_family, "hello", err_str);
    try std.testing.expect(null == noval);

    const lfs = try db.liveFiles(std.testing.allocator);
    defer lfs.deinit();
    defer for (lfs.items) |lf| lf.deinit();
    try std.testing.expect(std.mem.eql(u8, "another", lfs.items[0].column_family_name));
}
