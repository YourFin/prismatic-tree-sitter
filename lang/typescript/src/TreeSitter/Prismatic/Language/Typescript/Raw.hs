{-# LANGUAGE CApiFFI #-}

module TreeSitter.Prismatic.Language.Typescript.Raw (typescript) where

import Foreign.C.ConstPtr (ConstPtr (..))
import TreeSitter.Prismatic.Internal.Language.TH (rawLanguageSplice)

rawLanguageSplice "typescript" "tree-sitter-typescript.h" "tree_sitter_typescript"
