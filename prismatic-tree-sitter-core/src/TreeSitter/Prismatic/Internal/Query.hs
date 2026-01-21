{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query where

import Prelude hiding (lines, tail)

import Control.Exception (Exception)
import Data.ByteString qualified as ByteString
import Data.Function ((&))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.Foreign qualified as Text
import Data.Text.Lazy qualified as Lazy
import Data.Word (Word32)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr, withForeignPtr)

import Control.Monad.Cont (cont, evalCont)
import Errata
import Errata.Styles qualified as Errata
import Foreign (alloca, nullPtr, peek)
import Foreign.C (CUInt (CUInt))
import System.IO.Unsafe (unsafePerformIO)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang (..))

data RawQuery = RawQuery
  { unQuery :: !(ForeignPtr C'TSQuery)
  , -- Need to hold a handle on the raw language
    -- So the garbage collector doesn't kill it
    lang :: !RawLang
  }
  deriving (Eq)

data QueryError = QueryError
  { query :: !Text
  -- ^ Text of the query
  , errorOffset :: !Word32
  -- ^ Offset into query where the error occurred
  , kind :: !C'TSQueryError
  -- ^ Kind of error in the query
  }
  deriving (Eq, Ord)

cTsQueryErrorName :: C'TSQueryError -> Text
cTsQueryErrorName err
  | err == c'TSQueryErrorNone = "TSQueryErrorNone"
  | err == c'TSQueryErrorSyntax = "TSQueryErrorSyntax"
  | err == c'TSQueryErrorNodeType = "TSQueryErrorNodeType"
  | err == c'TSQueryErrorField = "TSQueryErrorField"
  | err == c'TSQueryErrorCapture = "TSQueryErrorCapture"
  | err == c'TSQueryErrorStructure = "TSQueryErrorStructure"
  | err == c'TSQueryErrorLanguage = "TSQueryErrorLanguage"
  | otherwise =
      "(TSQueryError value " <> (Text.pack . show) err <> ": from unknown ABI version)"

-- TODO: custom show impl
instance Show QueryError where
  -- This implementation is O(Query size)
  show (QueryError{..}) =
    errataSimple (Just "Tree-sitter unable to parse query") block Nothing
      & (Errata.prettyErrors query . pure)
      & Lazy.unpack
   where
    block =
      blockSimple'
        style
        Errata.basicPointer
        dummyfilepath
        Nothing
        (line, col, Just (cTsQueryErrorName kind))
        Nothing
    dummyfilepath = ""
    style =
      ( Errata.basicStyle
          { styleLocation = \(_fp, l, c) -> "line:" <> showT l <> ";col:" <> showT c
          , styleExtraLinesAfter = 3
          , styleExtraLinesBefore = 3
          }
      )
    showT = Text.pack . show
    -- bit of a hack job - doesn't account for errors in
    -- newline characters (annoying) or windows-style line endings
    -- (Erratta's fault)
    --
    -- NOTE: The Errata package does not appear to account for
    -- newlines or unicode grapheme clustering/bidi when calculating
    -- offsets
    (line, col) = byteLocation query (fromEnum errorOffset)
    byteLocation text byteOffset =
      let
        tail =
          Text.encodeUtf8 text
            & ByteString.drop byteOffset
            & Text.decodeUtf8Lenient
       in
        if byteOffset == 0
          then
            -- base case needed for later
            (0, 0)
          else
            if Text.length tail == 0
              then
                -- is EOF
                let lines = Text.lines text
                 in (length lines, lenLast lines)
              else case (Text.stripSuffix tail text) of
                Nothing ->
                  -- Only way this can happen is if the error
                  -- location reported by tree-sitter sits in the middle
                  -- of the bytes encoding a code point.
                  --
                  -- In that case, the right thing to do is to yell about
                  -- the start of the codepoint, which will be some number of
                  -- bytes backwards
                  byteLocation text (byteOffset - 1)
                Just toOffset ->
                  let lines = Text.lines toOffset
                   in (length lines, lenLast lines)

    lenLast = foldl' (\_ t -> Text.length t) 0

instance Exception QueryError

new :: RawLang -> Text -> Either QueryError RawQuery
new lang query = unsafePerformIO $ evalCont do
  langPtr <- cont $ withForeignConstPtr (unLang lang)
  (queryTextPtr, queryLen) <- cont $ Text.withCStringLen query
  errOffsetPtr <- cont $ alloca @Word32
  errTypePtr <- cont $ alloca @CUInt
  pure $ do
    queryPtr <-
      c'ts_query_new langPtr (ConstPtr queryTextPtr) (toEnum queryLen) errOffsetPtr errTypePtr
    if queryPtr == nullPtr
      then do
        errorOffset <- peek errOffsetPtr
        kind <- peek errTypePtr
        pure $ Left $ QueryError{..}
      else do
        unQuery <- newForeignPtr p'ts_query_delete queryPtr
        pure $ Right $ RawQuery{unQuery, lang}

patternCount :: RawQuery -> Word32
patternCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_pattern_count

captureCount :: RawQuery -> Word32
captureCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_capture_count

stringLiteralCount :: RawQuery -> Word32
stringLiteralCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_string_count

{-| UNSAFE - helper method for writing accessor methods against queries.
must not have side effects.
-}
withQueryPtrReferentiallyTransparent :: RawQuery -> (ConstPtr C'TSQuery -> a) -> a
withQueryPtrReferentiallyTransparent query closure =
  unsafePerformIO $ withForeignConstPtr (unQuery query) $ \ptr -> pure $ closure ptr

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)
