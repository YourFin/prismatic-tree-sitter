#ifndef TREE_SITTER_FFI_BRIDGE_H_
#define TREE_SITTER_FFI_BRIDGE_H_

#include <tree_sitter/api.h>

TSTree *ts_parser_parse_(TSParser *self, const TSTree *old_tree,
                         TSInput *input);

TSTree *ts_parser_parse_with_options_(TSParser *self, const TSTree *old_tree,
                                      TSInput *input,
                                      TSParseOptions *parse_options);

void ts_parser_logger_(const TSParser *self, TSLogger *out);

void ts_tree_copy_(const TSTree *self, TSTree *out);

void ts_tree_root_node_(const TSTree *self, TSNode *out);

void ts_tree_root_node_with_offset_(const TSTree *self, uint32_t offset_bytes,
                                    TSPoint *offset_extent, TSNode *out);

void ts_node_start_point_(TSNode *self, TSPoint *out);
void ts_node_end_point_(TSNode *self, TSPoint *out);

void ts_node_parent_(TSNode *self, TSNode *out);

#endif // TREE_SITTER_FFI_BRIDGE_H_
