const std = @import("std");
const rdb = @import("rocksdb");

pub const RocksDB = struct {
    allocator: std.mem.Allocator,
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
        allocator: std.mem.Allocator,
        dir: []const u8,
        db_options: DBOptions,
        column_families: []const ColumnFamilyDescription,
        err_str: *?RocksData,
    ) (std.mem.Allocator.Error || error{RocksDBOpen})!struct { Self, []const ColumnFamily } {
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

    pub fn putCf(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        value: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBSet}!void {
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_put_cf(
            self.db,
            rdb.rocksdb_writeoptions_create(),
            family,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &ch.err_str_in,
        ), error.RocksDBSet);
    }

    pub fn getCf(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBGet}!?RocksData {
        var valueLength: usize = 0;
        var ch = CallHandler.init(err_str);
        const value = try ch.handle(rdb.rocksdb_get_cf(
            self.db,
            rdb.rocksdb_readoptions_create(),
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
    _ = try db.putCf(a_family, "hello", "world", err_str);
    const val = try db.getCf(a_family, "hello", err_str);
    try std.testing.expect(std.mem.eql(u8, val.?.bytes, "world"));
}
