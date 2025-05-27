const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    const stdout_writer = std.io.getStdOut().writer();
    const stdin_reader = std.io.getStdIn().reader();

    try stdout_writer.print("Run `zig build test` to run the tests.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var my_data = MyData{ .data = std.ArrayListUnmanaged(u32){} };
    var data_mutex = std.Thread.Mutex{};
    var data_updated_signal = std.atomic.Value(bool).init(false);
    var app_ctx = AppContext{
        .data = &my_data,
        .allocator = allocator,
        .data_mutex = &data_mutex,
        .data_updated_signal = &data_updated_signal,
    };
    var server = try MyServer.init(&app_ctx);
    var server_thread = try std.Thread.spawn(.{}, runServer, .{&server});
    defer server_thread.join();
    defer server.stopServer();

    while (true) {
        if (data_updated_signal.load(.acquire)) {
            data_updated_signal.store(false, .release);
            std.debug.print("data has {d} items\n", .{my_data.data.items.len});
        }
        const line = stdin_reader.readUntilDelimiterAlloc(allocator, '\n', 1024) catch |err| {
            if (err == error.EndOfStream) {
                try stdout_writer.print("\n input stream closed, exiting\n", .{});
            }

            try stdout_writer.print("\nError reading input: {}\n", .{err});
            return err; // Propagate the error
        };
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "q")) {
            try stdout_writer.print("user requested quit, exiting loop\n", .{});
            break;
        } else if (std.mem.eql(u8, line, "a")) {
            data_mutex.lock();
            std.debug.print("main thread is adding\n", .{});
            try my_data.add(allocator);
            std.debug.print("main thread is done adding\n", .{});
            data_mutex.unlock();
        } else {
            try stdout_writer.print("unrecognized input, {s}\n", .{line});
        }
    }
    std.debug.print("loop exited\n", .{});
}

const MyData = struct {
    data: std.ArrayListUnmanaged(u32),

    fn add(self: *MyData, allocator: std.mem.Allocator) !void {
        try self.data.append(allocator, @intCast(self.data.items.len));
    }
};

const AppContext = struct {
    data: *MyData,
    allocator: std.mem.Allocator,
    data_mutex: *std.Thread.Mutex,
    data_updated_signal: *std.atomic.Value(bool),
};

const MyServer = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,
    server: httpz.Server(*AppContext),

    fn init(app_context: *AppContext) !MyServer {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        var server = try httpz.Server(*AppContext).init(allocator, .{ .port = 4042 }, app_context);

        var router = try server.router(.{});
        router.get("/test", httpTest, .{});

        return .{
            .gpa = gpa,
            .allocator = allocator,
            .server = server,
        };
    }

    fn deinit(self: *MyServer) !void {
        self.server.stop();
        self.server.deinit();
    }

    fn startServer(self: *MyServer) !void {
        std.debug.print("server listening on port 4042\n", .{});
        try self.server.listen();
        std.debug.print("server is done listening\n", .{});
    }

    fn stopServer(self: *MyServer) void {
        std.debug.print("Stopping server\n", .{});
        self.server.stop();
    }
};

fn runServer(server: *MyServer) !void {
    std.debug.print("callisg startServer\n", .{});
    try server.startServer();
}

fn httpTest(app_ctx: *AppContext, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    try res.json(.{ .hello = "test" }, .{});
    std.debug.print("server is adding\n", .{});
    app_ctx.data_mutex.lock();
    defer app_ctx.data_mutex.unlock();
    try app_ctx.data.add(app_ctx.allocator);
    app_ctx.data_updated_signal.store(true, .release);
    std.debug.print("server done adding\n", .{});
}
