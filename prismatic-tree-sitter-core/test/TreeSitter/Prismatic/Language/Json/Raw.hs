{-# LANGUAGE CApiFFI #-}

module TreeSitter.Prismatic.Language.Json.Raw (json, withJsonRawLang) where

import Foreign.C.ConstPtr (ConstPtr (..))
import TreeSitter.Prismatic.Internal.Language.TH (rawLanguageSplice)

import Test.Hspec
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang (..))

rawLanguageSplice
  [ "tst-vendor/json-grammar/grammar/src/parser.c"
  ]
  "json"
  "tree-sitter-json.h"
  "tree_sitter_json"

withJsonRawLang :: (RawLang -> IO ()) -> IO ()
withJsonRawLang action = snd <$> json >>= action
