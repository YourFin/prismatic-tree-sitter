#ifndef TREE_SITTER_FFI_BRIDGE_H_
#define TREE_SITTER_FFI_BRIDGE_H_

#include <tree_sitter/api.h>

typedef struct TSInput_ {
  void *payload;
  const char *(*read)(void *payload, uint32_t byte_index, TSPoint *position,
                      uint32_t *bytes_read);
  TSInputEncoding encoding;
  DecodeFunction decode;
} TSInput_;

TSTree *ts_parser_parse_(TSParser *self, const TSTree *old_tree,
                         TSInput_ *input);

TSTree *ts_parser_parse_with_options_(TSParser *self, const TSTree *old_tree,
                                      TSInput_ *input,
                                      TSParseOptions *parse_options);

void ts_parser_logger_(const TSParser *self, TSLogger *out);

void ts_tree_root_node_(const TSTree *self, TSNode *out);

void ts_tree_root_node_with_offset_(const TSTree *self, uint32_t offset_bytes,
                                    TSPoint *offset_extent, TSNode *out);

void ts_node_start_point_(TSNode *self, TSPoint *out);
void ts_node_end_point_(TSNode *self, TSPoint *out);

void ts_node_parent_(TSNode *self, TSNode *out);

void ts_node_child_with_descendant_(TSNode *self, TSNode *descendant,
                                    TSNode *out);
void ts_node_child_(TSNode *self, uint32_t child_index, TSNode *out);
void ts_node_named_child_(TSNode *self, uint32_t child_index, TSNode *out);
void ts_node_child_by_field_name_(TSNode *self, const char *name,
                                  uint32_t name_length, TSNode *out);
void ts_node_child_by_field_id_(TSNode *self, TSFieldId field_id, TSNode *out);
void ts_node_next_sibling_(TSNode *self, TSNode *out);
void ts_node_prev_sibling_(TSNode *self, TSNode *out);
void ts_node_next_named_sibling_(TSNode *self, TSNode *out);
void ts_node_prev_named_sibling_(TSNode *self, TSNode *out);
void ts_node_first_child_for_byte_(TSNode *self, uint32_t byte, TSNode *out);
void ts_node_first_named_child_for_byte_(TSNode *self, uint32_t byte,
                                         TSNode *out);
void ts_node_descendant_for_byte_range_(TSNode *self, uint32_t start,
                                        uint32_t end, TSNode *out);
void ts_node_descendant_for_point_range_(TSNode *self, TSPoint *start,
                                         TSPoint *end, TSNode *out);
void ts_node_named_descendant_for_byte_range_(TSNode *self, uint32_t start,
                                              uint32_t end, TSNode *out);
void ts_node_named_descendant_for_point_range_(TSNode *self, TSPoint *start,
                                               TSPoint *end, TSNode *out);

void ts_tree_cursor_new_(TSNode *node, TSTreeCursor *out);
void ts_tree_cursor_current_node_(const TSTreeCursor *self, TSNode *out);
void ts_tree_cursor_copy_(const TSTreeCursor *cursor, TSTreeCursor *out);

void ts_parser_set_logger_(TSParser *self, TSLogger *logger);

const char *ts_node_type_(TSNode *self);
TSSymbol ts_node_symbol_(TSNode *self);
const TSLanguage *ts_node_language_(TSNode *self);
const char *ts_node_grammar_type_(TSNode *self);
TSSymbol ts_node_grammar_symbol_(TSNode *self);
uint32_t ts_node_start_byte_(TSNode *self);
uint32_t ts_node_end_byte_(TSNode *self);
char *ts_node_string_(TSNode *self);
bool ts_node_is_null_(TSNode *self);
bool ts_node_is_named_(TSNode *self);
bool ts_node_is_missing_(TSNode *self);
bool ts_node_is_extra_(TSNode *self);
bool ts_node_has_changes_(TSNode *self);
bool ts_node_has_error_(TSNode *self);
bool ts_node_is_error_(TSNode *self);
TSStateId ts_node_parse_state_(TSNode *self);
TSStateId ts_node_next_parse_state_(TSNode *self);
const char *ts_node_field_name_for_child_(TSNode *self, uint32_t child_index);
const char *ts_node_field_name_for_named_child_(TSNode *self,
                                                uint32_t named_child_index);
uint32_t ts_node_child_count_(TSNode *self);
uint32_t ts_node_named_child_count_(TSNode *self);
uint32_t ts_node_descendant_count_(TSNode *self);
bool ts_node_eq_(TSNode *self, TSNode *other);

void ts_tree_cursor_reset_(TSTreeCursor *self, TSNode *node);
int64_t ts_tree_cursor_goto_first_child_for_point_(TSTreeCursor *self,
                                                   TSPoint *goal_point);

void ts_query_cursor_exec_(TSQueryCursor *self, const TSQuery *query,
                           TSNode *node);
bool ts_query_cursor_set_point_range_(TSQueryCursor *self, TSPoint *start_point,
                                      TSPoint *end_point);

void ts_query_cursor_exec_with_options_(TSQueryCursor *self, const TSQuery *query, TSNode *node, const TSQueryCursorOptions *query_options);

#endif // TREE_SITTER_FFI_BRIDGE_H_
