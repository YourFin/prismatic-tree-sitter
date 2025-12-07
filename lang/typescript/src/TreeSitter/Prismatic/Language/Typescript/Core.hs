{-# LANGUAGE CApiFFI #-}

module TreeSitter.Prismatic.Language.Typescript.Core (typescript, Typescript) where

import Foreign.C.ConstPtr (ConstPtr (..))
import TreeSitter.Prismatic.Internal.Language.TH (languageSplice)

languageSplice "typescript" "tree-sitter-typescript.h" "tree_sitter_typescript"
