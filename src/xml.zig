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

pub fn isLetter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

pub const Xml = struct {
    bytes: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,
    state: State = .tag_start,
    error_note: ErrorNote = undefined,
    tag_stacks: ArrayList(Tag) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allcator: std.mem.Allocator, bytes: []const u8) Xml {
        return Xml{
            .allocator = allcator,
            .bytes = bytes,
        };
    }

    pub fn deinit(xml: *Xml) void {
        xml.tag_stacks.deinit(xml.allocator);
    }

    pub fn addOpenTag(xml: *Xml, tag: Tag) !void {
        try xml.tag_stacks.append(xml.allocator, tag);
    }

    pub fn getTokenString(xml: *Xml) []const u8 {
        const tok_start: usize = xml.index;
        while (xml.index < xml.bytes.len) {
            xml.advanceCursor();
            const b = xml.bytes[xml.index];
            if (b == ' ' or b == '\t' or b == '\r' or b == '\n') break;
        }
        return xml.bytes[tok_start..xml.index];
    }

    pub fn peekChar(xml: *Xml) u8 {
        if (xml.index + 1 >= xml.bytes.len) {
            return 0;
        } else {
            return xml.bytes[xml.index + 1];
        }
    }

    pub fn next(xml: *Xml) !Token {
        var tok_start: usize = undefined;

        while (xml.index < xml.bytes.len) {
            const byte = xml.bytes[xml.index];
            // std.debug.print("current state: {s}\n", .{@tagName(xml.state)});
            // std.debug.print("byte: {c}\n", .{byte});
            switch (xml.state) {
                .tag_start => {
                    switch (byte) {
                        ' ', '\t', '\r', '\n' => {},
                        '<' => {
                            tok_start = xml.index;
                            xml.state = .tag_name;
                        },
                        else => {
                            tok_start = xml.index;
                            xml.state = .content;
                        },
                    }
                },

                .tag_name => {
                    switch (byte) {
                        '\t', '\r', '\n' => {},
                        '!' => {},
                        '?' => {
                            const next_byte = xml.peekChar();
                            if (next_byte == '>') {
                                xml.state = .prolog_end;
                            } else {
                                xml.advanceCursor();
                                const tok = xml.getTokenString();
                                if (std.mem.eql(u8, "xml", tok)) {
                                    return xml.emit(.prolog_body, .{
                                        .tag = .prolog_open,
                                        .bytes = tok,
                                    });
                                } else return xml.fail(.invalid_byte);
                            }
                        },
                        ' ' => {
                            if (tok_start + 1 != xml.index) {
                                return xml.emit(.tag_attr_key_q, .{
                                    .tag = .tag_open,
                                    .bytes = xml.bytes[tok_start + 1 .. xml.index],
                                });
                            }
                        },
                        '>' => {
                            if (tok_start + 1 != xml.index) {
                                return xml.emit(.tag_start, .{
                                    .tag = .tag_open,
                                    .bytes = xml.bytes[tok_start + 1 .. xml.index],
                                });
                            }
                        },
                        '/' => {
                            const next_byte = xml.peekChar();
                            const is_letter = isLetter(next_byte);
                            if (is_letter) {
                                tok_start = xml.index + 1;
                                xml.state = .closing_tag_start;
                            } else return xml.fail(.invalid_byte);
                        },

                        else => {},
                    }
                },
                .tag_body => {
                    switch (byte) {
                        '\t', '\r', '\n' => {},
                        '>' => xml.state = .tag_start,
                        '?' => xml.state = .prolog_end,
                        ' ' => {
                            tok_start = xml.index;
                            xml.state = .tag_attr_key_q;
                        },

                        else => {
                            xml.state = .tag_attr_key_q;
                        },
                    }
                },

                .prolog_body => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '?' => {
                        tok_start = xml.index;
                        xml.state = .prolog_end;
                    },
                    '<', '>' => return xml.fail(.invalid_byte),
                    else => {
                        tok_start = xml.index;
                        xml.state = .tag_attr_key;
                    },
                },
                .prolog_end => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<' => return xml.fail(.invalid_byte),
                    '>' => {
                        try xml.addOpenTag(Tag.tag_open);
                        const p = xml.tag_stacks.pop();
                        _ = p;
                        return xml.emit(
                            .tag_start,
                            .{
                                .tag = .prolog_end,
                                .bytes = "xml",
                            },
                        );
                    },
                    else => {},
                },

                .tag_end => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<' => xml.state = .tag_name,
                    '>' => {
                        try xml.addOpenTag(Tag.tag_open);
                        return xml.emit(
                            .tag_start,
                            .{
                                .tag = .tag_open,
                                .bytes = xml.bytes[tok_start..xml.index],
                            },
                        );
                    },
                    else => {},
                },
                .content => switch (byte) {
                    '<' => return xml.emit(.tag_name, .{
                        .tag = .content,
                        .bytes = xml.bytes[tok_start..xml.index],
                    }),
                    else => {},
                },

                .closing_tag_start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    '<', '-' => return xml.fail(.invalid_byte),
                    '>' => {
                        const t = xml.tag_stacks.pop();
                        _ = t;
                        return xml.emit(
                            .tag_start,
                            .{
                                .tag = .tag_close,
                                .bytes = xml.bytes[tok_start..xml.index],
                            },
                        );
                    },

                    else => {},
                },
                .self_closing_tag => switch (byte) {
                    else => {},
                },

                .tag_attr_key_q => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    else => {
                        tok_start = xml.index;
                        xml.state = .tag_attr_key;
                    },
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
                    '"', '\'' => {
                        xml.state = .tag_attr_value;
                        tok_start = xml.index;
                    },
                    else => return xml.fail(.invalid_byte),
                },
                .tag_attr_value => switch (byte) {
                    '"', '\'' => return xml.emit(.tag_body, .{
                        .tag = .attr_value,
                        .bytes = xml.bytes[tok_start .. xml.index + 1],
                    }),

                    '>' => {
                        xml.state = .tag_start;
                    },
                    '\n' => return xml.fail(.invalid_byte),
                    else => {},
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

test "normal tag" {
    const bytes =
        \\ <parents>
    ;
    const test_allocator = std.testing.allocator;
    var xml = Xml.init(test_allocator, bytes);
    defer xml.deinit();
    try testExpect(&xml, .tag_open, "parents");
    try testExpect(&xml, .eof, "");
}

test "hello world xml" {
    const bytes =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<map></map>
    ;
    const test_allocator = std.testing.allocator;
    var xml = Xml.init(test_allocator, bytes);
    defer xml.deinit();
    try testExpect(&xml, .prolog_open, "xml");
    try testExpect(&xml, .attr_key, "version");
    try testExpect(&xml, .attr_value, "\"1.0\"");
    try testExpect(&xml, .attr_key, "encoding");
    try testExpect(&xml, .attr_value, "\"UTF-8\"");
    try testExpect(&xml, .prolog_end, "xml");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
}
//
// test "single colon" {
//     const bytes =
//         \\ <?xml version='1.0' ?>
//     ;
//     const test_allocator = std.testing.allocator;
//     var xml = Xml.init(test_allocator, bytes);
//     defer xml.deinit();
//     try testExpect(&xml, .prolog, "xml");
//     try testExpect(&xml, .attr_key, "version");
//     try testExpect(&xml, .attr_value, "\'1.0\'");
//     try testExpect(&xml, .eof, "");
// }
//
// test "doctype xml" {
//     const bytes =
//         \\<?xml version="1.0" encoding="UTF-8"?>
//         \\<!DOCTYPE root_element PUBLIC "uri/to/external.dtd">
//         \\<map></map>
//     ;
//     const test_allocator = std.testing.allocator;
//     var xml = Xml.init(test_allocator, bytes);
//     defer xml.deinit();
//     try testExpect(&xml, .prolog, "xml");
//     try testExpect(&xml, .attr_key, "version");
//     try testExpect(&xml, .attr_value, "\"1.0\"");
//     try testExpect(&xml, .attr_key, "encoding");
//     try testExpect(&xml, .attr_value, "\"UTF-8\"");
//     try testExpect(&xml, .doctype, "DOCTYPE root_element PUBLIC \"uri/to/external.dtd\"");
//     try testExpect(&xml, .tag_open, "map");
//     try testExpect(&xml, .tag_close, "map");
//     try testExpect(&xml, .eof, "");
// }
//
// test "some props" {
//     const bytes =
//         \\<?xml?>
//         \\<map>
//         \\ <properties>
//         \\  <property name="gravity" type="float" value="12.34"/>
//         \\  <property name="never gonna give you up" type="bool" value="true"/>
//         \\  <property name="never gonna let you down" type="bool" value="true"/>
//         \\ </properties>
//         \\</map>
//     ;
//     const test_allocator = std.testing.allocator;
//     var xml = Xml.init(test_allocator, bytes);
//     defer xml.deinit();
//     try testExpect(&xml, .prolog, "xml");
//     try testExpect(&xml, .tag_open, "map");
//     try testExpect(&xml, .tag_open, "properties");
//
//     try testExpect(&xml, .tag_open, "property");
//     try testExpect(&xml, .attr_key, "name");
//     try testExpect(&xml, .attr_value, "\"gravity\"");
//     try testExpect(&xml, .attr_key, "type");
//     try testExpect(&xml, .attr_value, "\"float\"");
//     try testExpect(&xml, .attr_key, "value");
//     try testExpect(&xml, .attr_value, "\"12.34\"");
//     try testExpect(&xml, .self_closing_tag, "/");
//
//     try testExpect(&xml, .tag_open, "property");
//     try testExpect(&xml, .attr_key, "name");
//     try testExpect(&xml, .attr_value, "\"never gonna give you up\"");
//     try testExpect(&xml, .attr_key, "type");
//     try testExpect(&xml, .attr_value, "\"bool\"");
//     try testExpect(&xml, .attr_key, "value");
//     try testExpect(&xml, .attr_value, "\"true\"");
//     try testExpect(&xml, .self_closing_tag, "/");
//
//     try testExpect(&xml, .tag_open, "property");
//     try testExpect(&xml, .attr_key, "name");
//     try testExpect(&xml, .attr_value, "\"never gonna let you down\"");
//     try testExpect(&xml, .attr_key, "type");
//     try testExpect(&xml, .attr_value, "\"bool\"");
//     try testExpect(&xml, .attr_key, "value");
//     try testExpect(&xml, .attr_value, "\"true\"");
//     try testExpect(&xml, .self_closing_tag, "/");
//
//     try testExpect(&xml, .tag_close, "properties");
//     try testExpect(&xml, .tag_close, "map");
//     try testExpect(&xml, .eof, "");
// }
//
// test "comments" {
//     const bytes =
//         \\<?xml?>
//         \\ <!-- This is a multi-
//         \\       line comment, Rick -->
//         \\ <property name="rolled" type="bool" value="true"/>
//     ;
//     const test_allocator = std.testing.allocator;
//     var xml = Xml.init(test_allocator, bytes);
//     defer xml.deinit();
//     try testExpect(&xml, .prolog, "xml");
//     try testExpect(&xml, .tag_open, "property");
//     try testExpect(&xml, .attr_key, "name");
//     try testExpect(&xml, .attr_value, "\"rolled\"");
//     try testExpect(&xml, .attr_key, "type");
//     try testExpect(&xml, .attr_value, "\"bool\"");
//     try testExpect(&xml, .attr_key, "value");
//     try testExpect(&xml, .attr_value, "\"true\"");
//     try testExpect(&xml, .self_closing_tag, "/");
// }
//
// test "eof mid-comment" {
//     const bytes =
//         \\<?xml?>
//         \\ <!
//     ;
//
//     const test_allocator = std.testing.allocator;
//     var xml = Xml.init(test_allocator, bytes);
//     defer xml.deinit();
//     try testExpect(&xml, .prolog, "xml");
//     try testExpect(&xml, .eof, "");
// }
