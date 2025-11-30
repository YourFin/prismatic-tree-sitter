#include "tree_sitter_ffi_bridge.h"

TSTree *ts_parser_parse_(TSParser *self, const TSTree *old_tree,
                         TSInput *input) {
  return ts_parser_parse(self, old_tree, *input);
}

TSTree *ts_parser_parse_with_options_(TSParser *self, const TSTree *old_tree,
                                      TSInput *input,
                                      TSParseOptions *parse_options) {
  return ts_parser_parse_with_options(self, old_tree, *input, *parse_options);
};

void ts_parser_logger_(const TSParser *self, TSLogger *out) {
  *out = ts_parser_logger(self);
}

void ts_tree_copy_(const TSTree *self, TSTree *out) {
  *out = ts_tree_copy(self);
}

void ts_tree_root_node_(const TSTree *self, TSNode *out) {
  *out = ts_tree_root_node(self);
}

void ts_tree_root_node_with_offset_(const TSTree *self, uint32_t offset_bytes,
                                    TSPoint *offset_extent, TSNode *out) {
  *out = ts_tree_root_node_with_offset(self, offset_bytes, *offset_extent);
}
