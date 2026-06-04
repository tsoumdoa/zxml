const std = @import("std");
const Xml = @import("xml.zig").Xml;
const testing = std.testing;
const ArrayList = std.ArrayList;
const State = @import("enums.zig").State;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args_iter = std.process.Args.iterate(init.minimal.args);
    _ = args_iter.next().?;
    const input_file = args_iter.next().?;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var xml = Xml.init(
        allocator,
        try std.Io.Dir.cwd().readFileAlloc(io, input_file, allocator, .unlimited),
    );

    var stdout_buffer: [150]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    while (true) {
        const token = try xml.next();
        if (token.tag == .invalid) {
            try stdout.print("{s}: {s}\n", .{ @tagName(token.tag), token.bytes });
            break;
        }

        try stdout.print(
            "{?}@{any}, {s}: {s}\n",
            .{
                token.global_index,
                token.depth,
                @tagName(token.tag),
                token.bytes,
            },
        );
        if (token.tag == .eof) break;
        try stdout.flush();
    }

    try stdout.print("{d}\n", .{xml.tag_stacks.items.len});

    try stdout.flush();
}

test {
    testing.refAllDecls(Xml);
}
