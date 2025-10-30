pub const State = enum {
    // to be deleted----
    // start,
    // prolog_doctype_start,
    // prolog_start,
    // doctype_start,
    // prolog_name,
    // doctype,
    // prolog_attr_key,
    // prolog_attr_value_start,
    // prolog_attr_value_end,
    // prolog_doctype_end,
    // to be deleted----
    tag_start,
    tag_name,
    tag_body,
    tag_end,
    prolog_body,
    prolog_end,
    // tag_name_start,
    // tag_name,
    // tag,
    tag_attr_key_q,
    tag_attr_key,
    tag_attr_value_q,
    tag_attr_value,
    // tag_close_start,
    // tag_close_name,
    // tag_close_b,
    closing_tag_start,
    // closing_tag_name,
    // closing_tag_end,
    self_closing_tag,
    // body,
    content,
    // comment_start,
    // comment_body,
    // comment_end_maybe,
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
    prolog_open,
    prolog_end,
    /// Example: "<head>"
    /// Possible next tags:
    /// * `attr_key`
    /// * `tag_open`
    /// * `tag_close`
    /// * `content`
    doctype,

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
