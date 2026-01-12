{-# LANGUAGE CApiFFI #-}

module TreeSitter.Prismatic.Language.Typescript.Raw (typescript) where

import Foreign.C.ConstPtr (ConstPtr (..))
import TreeSitter.Prismatic.Internal.Language.TH (rawLanguageSplice)

rawLanguageSplice
    [ "vendor/arborium/langs/group-acorn/typescript/def/grammar/scanner.c"
    , "vendor/arborium/langs/group-acorn/typescript/def/grammar/src/parser.c"
    ]
    "typescript"
    "tree-sitter-typescript.h"
    "tree_sitter_typescript"
