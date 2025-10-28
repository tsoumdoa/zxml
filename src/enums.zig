pub const State = enum {
    start,
    doctype_q,
    doctype_name,
    doctype_name_start,
    doctype,
    doctype_attr_key,
    doctype_attr_value_q,
    doctype_attr_value,
    doctype_end,
    body,
    content,
    tag_name_start,
    tag_name,
    tag,
    tag_attr_key,
    tag_attr_value_q,
    tag_attr_value,
    tag_close_start,
    tag_close_name,
    tag_close_b,
    self_closing_tag,
    comment_start,
    comment_body,
    comment_end_maybe,
};

pub const Tag = enum {
    /// Error tokenizing the XML. Details can be found at the line, column,
    /// and error_note field.
    invalid,
    /// Example: "xml".
    /// Possible next tags:
    /// * `attr_key`
    /// * `attr_value`
    /// * `tag_open`
    doctype,
    /// Example: "<head>"
    /// Possible next tags:
    /// * `attr_key`
    /// * `tag_open`
    /// * `tag_close`
    /// * `content`
    tag_open,
    /// Example: "</head>"
    /// Possible next tags:
    /// * `tag_open`
    /// * `tag_close`
    /// * `content`
    tag_close,
    /// Emitted for empty nodes such as "<head/>".
    /// `bytes` will contain the "/".
    /// Possible next tags:
    /// * `tag_open`
    /// * `tag_close`
    /// * `content`
    self_closing_tag,
    /// Only the name of the key, does not include the '=' or the value.
    /// Possible next tags:
    /// * `attr_value`
    attr_key,
    /// Exactly the bytes of the string, including the quotes. Does no decoding.
    /// Possible next tags:
    /// * `attr_key`
    /// * `tag_open`
    /// * `tag_close`
    /// * `content`
    attr_value,
    /// The data between tags. Exactly the bytes, does no decoding.
    /// Possible next tags:
    /// * `tag_open`
    /// * `tag_close`
    content,
    /// End of file was reached.
    eof,
};
