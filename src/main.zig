const std = @import("std");
const Xml = @import("xml.zig").Xml;
const testing = std.testing;
const ArrayList = std.ArrayList;
const State = @import("enums.zig").State;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);
    const input_file = args[1];

    const max_bytes = std.math.maxInt(u32);
    var xml = Xml.init(
        arena,
        try std.fs.cwd().readFileAlloc(arena, input_file, max_bytes),
    );

    var stdout_buffer: [150]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    while (true) {
        const token = try xml.next();
        if (token.tag == .invalid) {
            try stdout.print("{s}: {s}\n", .{ @tagName(token.tag), token.bytes });
            break;
        }

        try stdout.print(
            "{?}@{any},{any} {s}: {s}\n\n",
            .{
                token.global_index,
                token.depth,
                token.local_index,
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
