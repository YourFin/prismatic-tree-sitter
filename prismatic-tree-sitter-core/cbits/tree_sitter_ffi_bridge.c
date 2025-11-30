#include "tree_sitter_ffi_bridge.h"

typedef struct WrappedPayload {
  void *real_payload;
  const char *(*real_read)(void *payload, uint32_t byte_index, TSPoint *position, uint32_t *bytes_read);
} WrappedPayload;

const char *adapted_tsinput_read(void* payload, uint32_t byte_index, TSPoint position, uint32_t *bytes_read) {
  WrappedPayload *w = (WrappedPayload*)payload;
  return (*w->real_read)(w->real_payload, byte_index, &position, bytes_read);
}

void adapt_ts_input(TSInput_ *input, WrappedPayload *out_p, TSInput *out) {
  out_p->real_payload = input->payload;
  out_p->real_read = input->read;
  out->payload = out_p;
  out->read = &adapted_tsinput_read;
  out->encoding = input->encoding;
  out->decode = input->decode;
}

TSTree *ts_parser_parse_(TSParser *self, const TSTree *old_tree,
                         TSInput_ *input) {
  WrappedPayload w;
  TSInput inp;
  adapt_ts_input(input, &w, &inp);
  return ts_parser_parse(self, old_tree, inp);
}

TSTree *ts_parser_parse_with_options_(TSParser *self, const TSTree *old_tree,
                                      TSInput_ *input,
                                      TSParseOptions *parse_options) {
  WrappedPayload w;
  TSInput inp;
  adapt_ts_input(input, &w, &inp);
  return ts_parser_parse_with_options(self, old_tree, inp, *parse_options);
};

// Everything from hereon is a very simple wrapper to remove
// any instances of structs getting returned/passed by value

void ts_parser_logger_(const TSParser *self, TSLogger *out) {
  *out = ts_parser_logger(self);
}

void ts_tree_root_node_(const TSTree *self, TSNode *out) {
  *out = ts_tree_root_node(self);
}

void ts_tree_root_node_with_offset_(const TSTree *self, uint32_t offset_bytes,
                                    TSPoint *offset_extent, TSNode *out) {
  *out = ts_tree_root_node_with_offset(self, offset_bytes, *offset_extent);
}

void ts_node_start_point_(TSNode *self, TSPoint *out) {
  *out = ts_node_start_point(*self);
}

void ts_node_end_point_(TSNode *self, TSPoint *out) {
  *out = ts_node_end_point(*self);
}

void ts_node_parent_(TSNode *self, TSNode *out) {
  *out = ts_node_parent(*self);
}

void ts_node_child_with_descendant_(TSNode *self, TSNode *descendant, TSNode *out) {
  *out = ts_node_child_with_descendant(*self, *descendant);
}

void ts_node_child_(TSNode *self, uint32_t child_index, TSNode *out) {
  *out = ts_node_child(*self, child_index);
}

void ts_node_named_child_(TSNode *self, uint32_t child_index, TSNode *out) {
  *out = ts_node_named_child(*self, child_index);
}

void ts_node_child_by_field_name_(TSNode *self, const char *name, uint32_t name_length, TSNode *out) {
  *out = ts_node_child_by_field_name(*self, name, name_length);
}

void ts_node_child_by_field_id_(TSNode *self, TSFieldId field_id, TSNode *out) {
  *out = ts_node_child_by_field_id(*self, field_id);
}

void ts_node_next_sibling_(TSNode *self, TSNode *out) {
  *out = ts_node_next_sibling(*self);
}

void ts_node_prev_sibling_(TSNode *self, TSNode *out) {
  *out = ts_node_prev_sibling(*self);
}

void ts_node_next_named_sibling_(TSNode *self, TSNode *out) {
  *out = ts_node_next_named_sibling(*self);
}

void ts_node_prev_named_sibling_(TSNode *self, TSNode *out) {
  *out = ts_node_prev_named_sibling(*self);
}

void ts_node_first_child_for_byte_(TSNode *self, uint32_t byte, TSNode *out) {
  *out = ts_node_first_child_for_byte(*self, byte);
}

void ts_node_first_named_child_for_byte_(TSNode *self, uint32_t byte, TSNode *out) {
  *out = ts_node_first_named_child_for_byte(*self, byte);
}

void ts_node_descendant_for_byte_range_(TSNode *self, uint32_t start, uint32_t end, TSNode *out) {
  *out = ts_node_descendant_for_byte_range(*self, start, end);
}

void ts_node_descendant_for_point_range_(TSNode *self, TSPoint *start, TSPoint *end, TSNode *out) {
  *out = ts_node_descendant_for_point_range(*self, *start, *end);
}

void ts_node_named_descendant_for_byte_range_(TSNode *self, uint32_t start, uint32_t end, TSNode *out) {
  *out = ts_node_named_descendant_for_byte_range(*self, start, end);
}

void ts_node_named_descendant_for_point_range_(TSNode *self, TSPoint *start, TSPoint *end, TSNode *out) {
  *out = ts_node_named_descendant_for_point_range(*self, *start, *end);
}

void ts_tree_cursor_new_(TSNode *node, TSTreeCursor *out) {
  *out = ts_tree_cursor_new(*node);
}

void ts_tree_cursor_current_node_(const TSTreeCursor *self, TSNode *out) {
  *out = ts_tree_cursor_current_node(self);
}

void ts_tree_cursor_copy_(const TSTreeCursor *cursor, TSTreeCursor *out) {
  *out = ts_tree_cursor_copy(cursor);
}

void ts_parser_set_logger_(TSParser *self, TSLogger *logger) {
  ts_parser_set_logger(self, *logger);
}

const char *ts_node_type_(TSNode *self) {
  return ts_node_type(*self);
}

TSSymbol ts_node_symbol_(TSNode *self) {
  return ts_node_symbol(*self);
}

const TSLanguage *ts_node_language_(TSNode *self) {
  return ts_node_language(*self);
}

const char *ts_node_grammar_type_(TSNode *self) {
  return ts_node_grammar_type(*self);
}

TSSymbol ts_node_grammar_symbol_(TSNode *self) {
  return ts_node_grammar_symbol(*self);
}

uint32_t ts_node_start_byte_(TSNode *self) {
  return ts_node_start_byte(*self);
}

uint32_t ts_node_end_byte_(TSNode *self) {
  return ts_node_end_byte(*self);
}

char *ts_node_string_(TSNode *self) {
  return ts_node_string(*self);
}

bool ts_node_is_null_(TSNode *self) {
  return ts_node_is_null(*self);
}

bool ts_node_is_named_(TSNode *self) {
  return ts_node_is_named(*self);
}

bool ts_node_is_missing_(TSNode *self) {
  return ts_node_is_missing(*self);
}

bool ts_node_is_extra_(TSNode *self) {
  return ts_node_is_extra(*self);
}

bool ts_node_has_changes_(TSNode *self) {
  return ts_node_has_changes(*self);
}

bool ts_node_has_error_(TSNode *self) {
  return ts_node_has_error(*self);
}

bool ts_node_is_error_(TSNode *self) {
  return ts_node_is_error(*self);
}

TSStateId ts_node_parse_state_(TSNode *self) {
  return ts_node_parse_state(*self);
}

TSStateId ts_node_next_parse_state_(TSNode *self) {
  return ts_node_next_parse_state(*self);
}

const char *ts_node_field_name_for_child_(TSNode *self, uint32_t child_index) {
  return ts_node_field_name_for_child(*self, child_index);
}

const char *ts_node_field_name_for_named_child_(TSNode *self, uint32_t named_child_index) {
  return ts_node_field_name_for_named_child(*self, named_child_index);
}

uint32_t ts_node_child_count_(TSNode *self) {
  return ts_node_child_count(*self);
}

uint32_t ts_node_named_child_count_(TSNode *self) {
  return ts_node_named_child_count(*self);
}

uint32_t ts_node_descendant_count_(TSNode *self) {
  return ts_node_descendant_count(*self);
}

bool ts_node_eq_(TSNode *self, TSNode *other) {
  return ts_node_eq(*self, *other);
}

void ts_tree_cursor_reset_(TSTreeCursor *self, TSNode *node) {
  ts_tree_cursor_reset(self, *node);
}

int64_t ts_tree_cursor_goto_first_child_for_point_(TSTreeCursor *self, TSPoint *goal_point) {
  return ts_tree_cursor_goto_first_child_for_point(self, *goal_point);
}

void ts_query_cursor_exec_(TSQueryCursor *self, const TSQuery *query, TSNode *node) {
  ts_query_cursor_exec(self, query, *node);
}

bool ts_query_cursor_set_point_range_(TSQueryCursor *self, TSPoint *start_point, TSPoint *end_point) {
  return ts_query_cursor_set_point_range(self, *start_point, *end_point);
}

void ts_query_cursor_exec_with_options_(TSQueryCursor *self, const TSQuery *query, TSNode *node, const TSQueryCursorOptions *query_options) {
  ts_query_cursor_exec_with_options(self, query, *node, query_options);
}
