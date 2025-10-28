const e = @import("enums.zig");
const Tag = e.Tag;
const State = e.State;
const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const ArrayList = std.ArrayList;

const key = .{ ' ', '\t', '\r', '\n' };

pub const ErrorNote = enum {
    invalid_byte,
};

pub const Token = struct {
    tag: Tag,
    bytes: []const u8,
};

pub const Xml = struct {
    bytes: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,
    state: State = .start,
    error_note: ErrorNote = undefined,
    tag_stacks: ArrayList(Tag) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allcator: std.mem.Allocator, bytes: []const u8) Xml {
        return Xml{
            .allocator = allcator,
            .bytes = bytes,
        };
    }

    pub fn addOpenTag(xml: *Xml, tag: Tag) !void {
        try xml.tag_stacks.append(xml.allocator, tag);
    }

    pub fn next(xml: *Xml) !Token {
        var tok_start: usize = undefined;

        while (xml.index < xml.bytes.len) {
            const byte = xml.bytes[xml.index];
            switch (xml.state) {
                .start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<' => xml.state = .doctype_q,
                    else => return xml.fail(.invalid_byte),
                },
                .doctype_q => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '?' => xml.state = .doctype_name_start,
                    else => return xml.fail(.invalid_byte),
                },
                .doctype_name_start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '>', '<' => return xml.fail(.invalid_byte),
                    else => {
                        tok_start = xml.index;
                        xml.state = .doctype_name;
                    },
                },
                .doctype_name => switch (byte) {
                    ' ', '\t', '\r', '\n' => return xml.emit(.doctype, .{
                        .tag = .doctype,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '?' => return xml.emit(.doctype_end, .{
                        .tag = .doctype,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '>', '<' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .doctype => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '?' => xml.state = .doctype_end,
                    '<', '>' => return xml.fail(.invalid_byte),
                    else => {
                        tok_start = xml.index;
                        xml.state = .doctype_attr_key;
                    },
                },
                .doctype_attr_key => switch (byte) {
                    '=' => return xml.emit(.doctype_attr_value_q, .{
                        .tag = .attr_key,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '?', '<', '>' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .doctype_attr_value_q => switch (byte) {
                    '"' => {
                        xml.state = .doctype_attr_value;
                        tok_start = xml.index;
                    },
                    else => return xml.fail(.invalid_byte),
                },
                .doctype_attr_value => switch (byte) {
                    '"' => return xml.emit(.doctype, .{
                        .tag = .attr_value,
                        .bytes = xml.bytes[tok_start .. xml.index + 1],
                    }),
                    '\n' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .doctype_end => switch (byte) {
                    '>' => xml.state = .body,
                    else => return xml.fail(.invalid_byte),
                },
                .body => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<' => xml.state = .tag_name_start,
                    else => {
                        xml.state = .content;
                        tok_start = xml.index;
                    },
                },
                .content => switch (byte) {
                    '<' => return xml.emit(.tag_name_start, .{
                        .tag = .content,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    else => {},
                },
                .tag_name_start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '!' => xml.state = .comment_start,
                    '>', '<' => return xml.fail(.invalid_byte),
                    '/' => xml.state = .tag_close_start,
                    else => {
                        tok_start = xml.index;
                        xml.state = .tag_name;
                    },
                },
                .tag_close_start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '>', '<' => return xml.fail(.invalid_byte),
                    else => {
                        tok_start = xml.index;
                        xml.state = .tag_close_name;
                    },
                },
                .tag_close_name => switch (byte) {
                    ' ', '\t', '\r', '\n' => return xml.emit(.tag_close_b, .{
                        .tag = .tag_open,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '>' => {
                        const t = xml.tag_stacks.pop();
                        _ = t;
                        return xml.emit(.body, .{
                            .tag = .tag_close,
                            .bytes = xml.bytes[tok_start..xml.index],
                        });
                    },
                    '<' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .tag_close_b => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '>' => xml.state = .body,
                    else => return xml.fail(.invalid_byte),
                },
                .tag_name => switch (byte) {
                    ' ', '\t', '\r', '\n' => return xml.emit(.tag, .{
                        .tag = .tag_open,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '>' => {
                        try xml.addOpenTag(Tag.tag_open);
                        return xml.emit(.body, .{
                            .tag = .tag_open,
                            .bytes = xml.bytes[tok_start..xml.index],
                        });
                    },
                    '<' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .tag => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<' => return xml.fail(.invalid_byte),
                    '>' => xml.state = .body,
                    '/' => {
                        tok_start = xml.index;
                        xml.state = .self_closing_tag;
                    },
                    else => {
                        tok_start = xml.index;
                        xml.state = .tag_attr_key;
                    },
                },
                .self_closing_tag => switch (byte) {
                    '>' => {
                        const t = xml.tag_stacks.pop();
                        _ = t;
                        return xml.emit(.body, .{
                            .tag = .self_closing_tag,
                            .bytes = xml.bytes[tok_start..xml.index],
                        });
                    },
                    else => return xml.fail(.invalid_byte),
                },
                .tag_attr_key => switch (byte) {
                    '=' => return xml.emit(.tag_attr_value_q, .{
                        .tag = .attr_key,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    '<', '>' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .tag_attr_value_q => switch (byte) {
                    '"' => {
                        xml.state = .tag_attr_value;
                        tok_start = xml.index;
                    },
                    else => return xml.fail(.invalid_byte),
                },
                .tag_attr_value => switch (byte) {
                    '"' => return xml.emit(.tag, .{
                        .tag = .attr_value,
                        .bytes = xml.bytes[tok_start .. xml.index + 1],
                    }),
                    '\n' => return xml.fail(.invalid_byte),
                    else => {},
                },
                .comment_start => switch (byte) {
                    '-' => xml.state = .comment_body,
                    else => return xml.fail(.invalid_byte),
                },
                .comment_body => switch (byte) {
                    '-' => xml.state = .comment_end_maybe,
                    else => {},
                },
                .comment_end_maybe => switch (byte) {
                    '-' => {},
                    '>' => xml.state = .body,
                    else => xml.state = .comment_body,
                },
            }
            xml.advanceCursor();
        }
        return .{
            .tag = .eof,
            .bytes = xml.bytes[xml.bytes.len..],
        };
    }

    fn fail(xml: *Xml, note: ErrorNote) Token {
        xml.error_note = note;
        return .{ .tag = .invalid, .bytes = xml.bytes[xml.index..][0..0] };
    }

    fn emit(xml: *Xml, next_state: State, token: Token) Token {
        xml.state = next_state;
        xml.advanceCursor();
        return token;
    }

    fn advanceCursor(xml: *Xml) void {
        const byte = xml.bytes[xml.index];
        xml.index += 1;

        if (byte == '\n') {
            xml.line += 1;
            xml.column = 0;
        } else {
            xml.column += 1;
        }
    }
};

fn testExpect(xml: *Xml, tag: Tag, bytes: []const u8) !void {
    const tok = try xml.next();
    try testing.expectEqual(tag, tok.tag);
    try testing.expectEqualStrings(bytes, tok.bytes);
}

test "hello world xml" {
    const bytes =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<map></map>
    ;
    var xml = Xml.init(bytes);
    std.debug.print("hello world xml\n", .{});
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .attr_key, "version");
    try testExpect(&xml, .attr_value, "\"1.0\"");
    try testExpect(&xml, .attr_key, "encoding");
    try testExpect(&xml, .attr_value, "\"UTF-8\"");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
    try testExpect(&xml, .eof, "");
}

test "some props" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\  <property name="gravity" type="float" value="12.34"/>
        \\  <property name="never gonna give you up" type="bool" value="true"/>
        \\  <property name="never gonna let you down" type="bool" value="true"/>
        \\ </properties>
        \\</map>
    ;
    var xml = Xml.init(bytes);
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_open, "properties");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"gravity\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"float\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"12.34\"");
    try testExpect(&xml, .self_closing_tag, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna give you up\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .self_closing_tag, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna let you down\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .self_closing_tag, "/");

    try testExpect(&xml, .tag_close, "properties");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
}

test "comments" {
    const bytes =
        \\<?xml?>
        \\ <!-- This is a multi-
        \\       line comment, Rick -->
        \\ <property name="rolled" type="bool" value="true"/>
    ;
    var xml = Xml.init(bytes);
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"rolled\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .self_closing_tag, "/");
}

test "eof mid-comment" {
    const bytes =
        \\<?xml?>
        \\ <!
    ;
    var xml = Xml.init(bytes);
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .eof, "");
}
