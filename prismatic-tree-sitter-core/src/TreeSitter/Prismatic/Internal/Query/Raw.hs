{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query.Raw where

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

import Control.Monad (when)
import Control.Monad.Cont (cont, evalCont)
import Errata
import Errata.Styles qualified as Errata
import Foreign (alloca, nullPtr, peek)
import Foreign.C (CUInt (CUInt))
import Foreign.Marshal.Utils (toBool)
import GHC.Generics (Generic)
import System.IO.Unsafe (unsafePerformIO)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Foreign.Array (peekConstArray)
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang (..))

-- NOTE:
-- use overloaded labels to get query names
-- Encoding in type of query should be
-- Query '["singleton", Many "multiple captures", "another"]
-- Where index in type level list represents the actual index
-- into the query

data RawQuery = RawQuery
  { unQuery :: !(ForeignPtr C'TSQuery)
  , -- Need to hold a handle on the raw language
    -- So the garbage collector doesn't kill it
    lang :: !RawLang
  }
  deriving (Eq, Ord, Generic)

data QueryError = QueryError
  { query :: !Text
  -- ^ Text of the query
  , errorOffset :: !Word32
  -- ^ Offset into query where the error occurred
  , kind :: !C'TSQueryError
  -- ^ Kind of error in the query
  }
  deriving (Eq, Ord, Generic)

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
    errataSimple (Just "QueryError: Tree-sitter unable to parse query") block Nothing
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
    -- (Erratta's fault - uses Text's `lines` impl)
    --
    -- NOTE: The Errata package does not appear to account for
    -- newlines or unicode grapheme clustering/bidi when calculating
    -- offsets
    --
    -- It also doesn't /do/ all that much here, and may be worth replacing
    -- should something suitable come up
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

-- | Check if the given pattern in the query has a single root node.
isPatternRooted :: RawQuery -> Word32 -> Bool
isPatternRooted query patternIdx = withQueryPtrReferentiallyTransparent query $ \queryPtr ->
  c'ts_query_is_pattern_rooted queryPtr patternIdx
    & toBool
{-# WARNING in "x-partial" isPatternRooted "pattern index argument can go out of bounds and read arbitrary memory" #-}

{-| Check if the given pattern in the query is 'non local'.

  A non-local pattern has multiple root nodes and can match within a
  repeating sequence of nodes, as specified by the grammar. Non-local
  patterns disable certain optimizations that would otherwise be possible
  when executing a query on a specific range of a syntax tree.
-}
isPatternNonLocal :: RawQuery -> Word32 -> Bool
isPatternNonLocal query patternIdx = withQueryPtrReferentiallyTransparent query $ \queryPtr ->
  c'ts_query_is_pattern_non_local queryPtr patternIdx
    & toBool
{-# WARNING in "x-partial" isPatternNonLocal "pattern index argument can go out of bounds and read arbitrary memory" #-}

-- TODO: ts_query_is_pattern_guaranteed_at_step

{-| Get all of the predicates for the given pattern in the query.

The predicates are represented as a single array of steps. There are three
types of steps in this array, which correspond to the three legal values for
the `type` field:
- `TSQueryPredicateStepTypeCapture` - Steps with this type represent names
   of captures. Their `value_id` can be used with the
  [`ts_query_capture_name_for_id`] function to obtain the name of the capture.
- `TSQueryPredicateStepTypeString` - Steps with this type represent literal
   strings. Their `value_id` can be used with the
   [`ts_query_string_value_for_id`] function to obtain their string value.
- `TSQueryPredicateStepTypeDone` - Steps with this type are *sentinels*
   that represent the end of an individual predicate. If a pattern has two
   predicates, then there will be two steps with this `type` in the array.
-}
predicatesForPattern :: RawQuery -> Word32 -> [C'TSQueryPredicateStep]
predicatesForPattern query patternIdx = unsafePerformIO $ withQueryPtrReferentiallyTransparent query $ \queryPtr ->
  alloca $ \stepCountOut -> do
    arrPtr <- c'ts_query_predicates_for_pattern queryPtr patternIdx stepCountOut
    stepCount <- peek stepCountOut
    when (toInteger stepCount > toInteger (maxBound :: Int)) $
      fail
        ( "Query predicate steps ("
            <> show stepCount
            <> ") greater than IntMax: "
            <> show (maxBound :: Int)
        )
    peekConstArray (fromEnum stepCount) arrPtr
{-# WARNING in "x-partial"
  predicatesForPattern
  "pattern index argument can go out of bounds and read arbitrary memory"
  #-}

{-| Get the name and length of one of the query's captures, or one of the
  query's string literals. Each capture and string is associated with a
  numeric id based on the order that it appeared in the query's source.

  Port of ts_query_capture_name_for_id, which appears to have taken on the
  string-literal fetching functionality later in life.
-}
captureNameOrTextOfPredicate :: RawQuery -> Word32 -> Text
captureNameOrTextOfPredicate query predicateIdx = unsafePerformIO $ withQueryPtrReferentiallyTransparent query $ \queryPtr ->
  alloca $ \strLenPtr -> do
    (ConstPtr strPtr) <- c'ts_query_capture_name_for_id queryPtr predicateIdx strLenPtr
    strLen <- peek strLenPtr
    when (toInteger strLen > toInteger (maxBound :: Int)) $
      fail
        ( "Capture name or raw text has length ("
            <> show strLen
            <> "), greater than IntMax: "
            <> show (maxBound :: Int)
        )
    bytes <- ByteString.packCStringLen (strPtr, fromEnum strLen)
    pure $ Text.decodeUtf8Lenient bytes

{-| UNSAFE - helper method for writing accessor methods against queries.
must not have side effects.
-}
withQueryPtrReferentiallyTransparent :: RawQuery -> (ConstPtr C'TSQuery -> a) -> a
withQueryPtrReferentiallyTransparent query closure =
  unsafePerformIO $ withForeignConstPtr (unQuery query) $ \ptr -> pure $ closure ptr

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)
