{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoFieldSelectors #-}

module TreeSitter.Prismatic.Internal.Query.Raw (
  RawQuery (..),
  RawQuery' (..),
  new,
  -- | Patterns
  Pattern (..),
  PatternLocality (..),
  -- | Query Statements
  Statement (..),
  StatementArg (..),
  resolveStatementArg,
  QueryError (..),
  -- | Capture
  CaptureQuantifier (..),
) where

import Prelude hiding (lines, tail)

import Control.Exception (Exception)
import Control.Exception.Safe qualified
import Data.ByteString qualified as ByteString
import Data.Function ((&))
import Data.Functor ((<&>))
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.Foreign qualified as Text
import Data.Text.Lazy qualified as Lazy
import Data.Word (Word32)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr, withForeignPtr)

import Control.Exception.Base (SomeException)
import Control.Monad (forM)
import Control.Monad.Cont (cont, evalCont)
import Control.Monad.Except (
  ExceptT (..),
  MonadError (throwError),
  runExceptT,
 )
import Control.Monad.IO.Class (liftIO)
import Data.Finite (Finite, packFinite)
import Data.Finite.Integral (KnownIntegral)
import Data.Vector qualified as Unsized
import Data.Vector.Sized qualified as Sized
import Errata
import Errata.Styles qualified as Errata
import Foreign (Storable, alloca, nullPtr, peek)
import Foreign.C (CUInt)
import Foreign.Marshal.Utils (toBool)
import Foreign.Ptr (Ptr)
import GHC.Generics (Generic)
import GHC.TypeLits (SNat, pattern SNat)
import System.IO.Unsafe (unsafePerformIO)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Foreign.Array (peekConstArray)
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang (..))
import Type.Reflection (Typeable)

-- NOTE:
-- use overloaded labels to get query names
-- Encoding in type of query should be
-- Query '["singleton", Many "multiple captures", "another"]
-- Where index in type level list represents the actual index
-- into the query

data RawQuery' captureCount
  = RawQuery'
  { queryForeign :: !(ForeignPtr C'TSQuery)
  -- ^ C-Api pointer
  , captureNames :: !(Sized.Vector captureCount Text)
  -- ^ The names of the capture in this query; id'd by index
  , patterns :: !(Unsized.Vector (Pattern captureCount))
  -- ^ The `Pattern`s that make up this query; think top-level definitions
  , source :: !Text
  -- ^ The query's source text
  , lang :: !RawLang
  {- ^ A handle on the corresponding language, to prevent premature
  garbage collection
  -}
  }
  deriving (Eq, Ord, Generic)
type role RawQuery' nominal

{-|
  `RawQuery\'` contains the fields,
  but the the type needs to be wrapped
  so to existentially quantify the
  capture count
-}
data RawQuery where
  RawQuery ::
    SNat captureCount ->
    ( RawQuery'
        captureCount
    ) ->
    RawQuery
  deriving (Typeable)

-- TODO: Eq, Ord, Show impl for RawQuery

{-| Along with sets of nodes to match, patterns can
    contain __Predicates__ and __Directives__ to be
    evaluated. These /generally/ involve doing something
    with captures from the matched nodes.
    This library uses the `Statement` type as a superset
    of both, as they cannot be nested.

    By convention, __Predicate__ names end with @?@,
    and __Directive__ names end with @!@. However, the
    Tree-Sitter C Api doesn't make any distinction between
    __Predicates__ and __Directives__; they are parsed the
    same way, and evaluation is left to the calling code.

    Official documentation: <https://tree-sitter.github.io/tree-sitter/using-parsers/queries/3-predicates-and-directives.html>
-}
data Statement captureCount = Statement {operator :: !Text, args :: !(Unsized.Vector (StatementArg captureCount))}
  deriving (Eq, Ord, Generic, Show)

-- | An argument to a `Statement`
data StatementArg captureCount
  = StatementArgCapture !(Data.Finite.Finite captureCount)
  | StatementArgString !Text
  deriving (Eq, Ord, Show, Generic)

resolveStatementArg :: RawQuery' c -> StatementArg c -> Text
resolveStatementArg RawQuery'{..} (StatementArgCapture count) =
  Sized.index captureNames count
resolveStatementArg _ (StatementArgString n) = n

data Pattern captureCount = Pattern
  { querySpanBytes :: !(Word32, Word32)
  -- ^ Pattern start and end text byte in the overall query
  , locality :: PatternLocality
  -- ^ See `PatternLocality`
  , statements :: !(Unsized.Vector (Statement captureCount))
  -- ^ The `Statement`s to be evaluated as part of matching this pattern
  , captureQuantifiers :: !(Sized.Vector captureCount CaptureQuantifier)
  -- ^ How often each capture in the parent query matches in this pattern
  }
  deriving (Eq, Ord, Generic, Show)

{-| Normalized form of the data reported by the
  @ts_query_is_pattern_rooted@ and
  @ts_query_is_pattern_non_local@ C apis
-}
data PatternLocality
  = -- | The pattern matches is contained under a single root node
    SingleRootPattern
  | {-| While the pattern does not have a single root node,
        optimizations related to executing within a specific range
        of a syntax tree still work.
    -}
    LocalPattern
  | {-| A non-local pattern has multiple root nodes and can match
        within a repeating sequence of nodes, as specified by the grammar.
        Non-local patterns disable certain optimizations that would otherwise
        be possible when executing a query on a specific range of a syntax tree.

        (Editorial note) My suspicion is that local vs non-local patterns
        rhymes with regular vs context-free grammars.
    -}
    NonLocalPattern
  deriving (Eq, Ord, Show, Generic)

parsePatternLocality ::
  (MonadError QueryError m) => ConstPtr C'TSQuery -> Word32 -> m PatternLocality
parsePatternLocality queryPtr patternIdx =
  case ( toBool $ c'ts_query_is_pattern_rooted queryPtr patternIdx
       , toBool $ c'ts_query_is_pattern_non_local queryPtr patternIdx
       ) of
    (True, False) -> pure SingleRootPattern
    (False, False) -> pure LocalPattern
    (False, True) -> pure NonLocalPattern
    (True, True) ->
      unexpected $
        "Programming error; `ts_query_is_pattern_rooted` and `ts_query_is_pattern-non_local` both returned true, which this code thought impossible."

data QueryError
  = -- | Query compilation error reported by the C api
    QueryCompilationError
      { query :: !Text
      -- ^ Text of the query
      , errorOffset :: !Word32
      -- ^ Offset into query where the error occurred
      , kind :: !C'TSQueryError
      -- ^ Kind of error in the query
      }
  | -- | Unexpected condition (think: array out of bounds, casting issue, etc.)
    QueryErrorUnexpected !String
  | QueryErrorIOException !SomeException
  deriving (Generic)

-- | Internal monad stack for query compilation
type QueryM a = ExceptT QueryError IO a

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

instance Show QueryError where
  -- This implementation is O(Query size)
  show (QueryCompilationError{..}) =
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
  show (QueryErrorUnexpected msg) = "QueryErrorUnexpected: " <> msg
  show (QueryErrorIOException e) = "QueryErrorIOException (" <> show e <> ")"

instance Exception QueryError

data CaptureQuantifier
  = CaptureQuantifierZero
  | CaptureQuantifierZeroOrOne
  | CaptureQuantifierZeroOrMore
  | CaptureQuantifierOne
  | CaptureQuantifierOneOrMore
  deriving (Eq, Ord, Show)

parseCaptureQuantifier ::
  (MonadError QueryError m) => C'TSQuantifier -> m CaptureQuantifier
parseCaptureQuantifier cval
  | cval == c'TSQuantifierZero = pure CaptureQuantifierZero
  | cval == c'TSQuantifierZeroOrOne = pure CaptureQuantifierZeroOrOne
  | cval == c'TSQuantifierZeroOrMore = pure CaptureQuantifierZeroOrMore
  | cval == c'TSQuantifierOne = pure CaptureQuantifierOne
  | cval == c'TSQuantifierOneOrMore = pure CaptureQuantifierOneOrMore
  | otherwise = unknownEnumVal "TSQuantifier" cval

new :: RawLang -> Text -> Either QueryError RawQuery
new lang query = unsafePerformIO $ (flip Control.Exception.Safe.catch) (pure . Left . QueryErrorIOException) $ evalCont do
  langPtr <- cont $ withForeignConstPtr (unLang lang)
  (queryTextPtr, queryLen) <- cont $ Text.withCStringLen query
  errOffsetPtr <- cont $ alloca @Word32
  errTypePtr <- cont $ alloca @CUInt
  pure $ do
    queryPtrMut <-
      c'ts_query_new langPtr (ConstPtr queryTextPtr) (toEnum queryLen) errOffsetPtr errTypePtr
    let queryPtr = ConstPtr queryPtrMut
    if queryPtrMut == nullPtr
      then do
        errorOffset <- peek errOffsetPtr
        kind <- peek errTypePtr
        pure $ Left $ QueryCompilationError{..}
      else runExceptT $ do
        queryForeign <- liftIO $ newForeignPtr p'ts_query_delete queryPtrMut

        let captureCountW32 = c'ts_query_capture_count queryPtr
        captureCountInt <- word32ToInt "capture count" captureCountW32
        captureNames' <- forM [0 .. captureCountInt - 1] \capIdx' ->
          alloca' $ \strLenPtr -> do
            capIdx <- intToWord32 "capture idx" capIdx'
            (ConstPtr strPtr) <- liftIO $ c'ts_query_capture_name_for_id queryPtr capIdx strLenPtr
            strLen' <- liftIO $ peek strLenPtr
            strLen <- word32ToInt "capture name length" strLen'
            bytes <- liftIO $ ByteString.packCStringLen (strPtr, strLen)
            pure $ Text.decodeUtf8Lenient bytes

        stringLiteralCount <-
          c'ts_query_string_count queryPtr & word32ToInt "string literal count"

        stringLiterals <- Unsized.generateM stringLiteralCount \strLitIdx' ->
          alloca' $ \strLenPtr -> do
            strLitIdx <- intToWord32 "string literal index" strLitIdx'
            (ConstPtr strPtr) <- liftIO $ c'ts_query_string_value_for_id queryPtr strLitIdx strLenPtr
            strLen' <- liftIO $ peek strLenPtr
            strLen <- word32ToInt "string literal length" strLen'
            bytes <- liftIO $ ByteString.packCStringLen (strPtr, strLen)
            pure $ Text.decodeUtf8Lenient bytes

        let stringLitByIdx =
              ( \prefix idx -> do
                  intIdx <- word32ToInt "string literal index" idx
                  case (stringLiterals Unsized.!? intIdx) of
                    (Just str) -> pure str
                    Nothing ->
                      unexpected $
                        prefix
                          <> ": Requested string literal #"
                          <> show intIdx
                          <> ( case Unsized.length stringLiterals of
                                 0 -> "; when query contained none"
                                 len -> ", max is " <> (show (len - 1))
                             )
              ) ::
                String -> Word32 -> QueryM Text

        patternCount <- c'ts_query_pattern_count queryPtr & word32ToInt "pattern count"

        Sized.withSizedList captureNames' $ \captureNames -> do
          patterns <- Unsized.generateM patternCount $ \patIdx' -> do
            patIdx <- intToWord32 "pattern index" patIdx'

            rawPredSteps <- alloca' $ \stepCountPtr -> do
              predsPtr <- liftIO $ c'ts_query_predicates_for_pattern queryPtr patIdx stepCountPtr
              stepCount <- (liftIO . peek) stepCountPtr >>= word32ToInt "predicate steps"
              if stepCount == 0
                then
                  pure []
                else do
                  liftIO $ peekConstArray stepCount predsPtr

            statements <-
              rawPredSteps
                & splitOn ((c'TSQueryPredicateStepTypeDone ==) . c'TSQueryPredicateStep'type)
                <&> zip [(0 :: Int) ..]
                & zip [(0 :: Int) ..]
                -- Inject indexes for error messages ^^
                & traverse
                  ( \(predIdx, predStep) ->
                      let errPrefix = "In pattern " <> show patIdx <> ", predicate " <> show predIdx
                       in case predStep of
                            [] -> pure Nothing
                            ((_, StringStep operatorId) : (Unsized.fromList -> argSteps)) -> do
                              operator <- stringLitByIdx (errPrefix <> ", loc 0") operatorId
                              args <- forM argSteps $ \(locIdx, step) ->
                                let errPrefix' = errPrefix <> ", location " <> show locIdx
                                 in case step of
                                      (StringStep idx) -> do
                                        name <- stringLitByIdx errPrefix' idx
                                        pure $ StatementArgString name
                                      (CaptureStep idx) -> case Data.Finite.packFinite (toInteger idx) of
                                        Just finiteIdx ->
                                          pure $ StatementArgCapture finiteIdx
                                        Nothing ->
                                          unexpected $
                                            errPrefix'
                                              <> ": Statement contained reference to capture #"
                                              <> show idx
                                              <> ( case captureCountInt of
                                                     0 -> "; query has no captures"
                                                     _ -> ", max is " <> show (captureCountInt - 1)
                                                 )
                                      (C'TSQueryPredicateStep{..}) ->
                                        unexpected $
                                          errPrefix'
                                            <> show c'TSQueryPredicateStep'type
                                            <> "; expected type String ("
                                            <> show (c'TSQueryPredicateStepTypeString @Int)
                                            <> ") or Capture ("
                                            <> show (c'TSQueryPredicateStepTypeCapture @Int)
                                            <> ")"
                              pure $ Just Statement{..}
                            ((_, C'TSQueryPredicateStep{..}) : _) ->
                              unexpected $
                                "In pattern "
                                  <> show patIdx
                                  <> ": Unexpected query predicate step type "
                                  <> show c'TSQueryPredicateStep'type
                                  <> "; expected type String ("
                                  <> show (c'TSQueryPredicateStepTypeString @Int)
                                  <> ")"
                  )
                <&> catMaybes
                <&> Unsized.fromList
            -- end statements

            captureQuantifiers <- Sized.generateM $ \captureIdx ->
              c'ts_query_capture_quantifier_for_id queryPtr patIdx (finiteToWord32 captureIdx)
                & parseCaptureQuantifier

            locality <- parsePatternLocality queryPtr patIdx

            pure
              Pattern
                { statements
                , captureQuantifiers
                , locality
                , querySpanBytes =
                    ( c'ts_query_start_byte_for_pattern queryPtr patIdx
                    , c'ts_query_end_byte_for_pattern queryPtr patIdx
                    )
                }

          pure $ RawQuery SNat RawQuery'{source = query, ..}

splitOn :: (a -> Bool) -> [a] -> [[a]]
splitOn p = foldr f []
 where
  f a acc = case (acc, p a) of
    (_, True) -> [] : acc
    ([], False) -> [[a]]
    (cur : rest, _) -> (a : cur) : rest

pattern StringStep :: Word32 -> C'TSQueryPredicateStep
pattern StringStep valueId <-
  C'TSQueryPredicateStep ((== c'TSQueryPredicateStepTypeString) -> True) valueId

pattern CaptureStep :: Word32 -> C'TSQueryPredicateStep
pattern CaptureStep valueId <-
  C'TSQueryPredicateStep ((== c'TSQueryPredicateStepTypeCapture) -> True) valueId

-- TODO: ts_query_is_pattern_guaranteed_at_step

unexpected :: (MonadError QueryError m) => String -> m a
unexpected = throwError . QueryErrorUnexpected

unknownEnumVal :: (MonadError QueryError m, Show a) => String -> a -> m b
unknownEnumVal enumName unknownValue =
  unexpected $
    "Got unknown value " <> show unknownValue <> " for the " <> enumName <> " enum"

finiteToWord32 :: (KnownIntegral Integer n) => Data.Finite.Finite n -> Word32
finiteToWord32 = fromInteger . toInteger

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)

word32ToInt :: (MonadError QueryError m) => String -> Word32 -> m Int
word32ToInt = safeCastIntegerlike "int"

intToWord32 :: (MonadError QueryError m) => String -> Int -> m Word32
intToWord32 = safeCastIntegerlike "uint32"

safeCastIntegerlike ::
  forall b a m.
  (MonadError QueryError m, Bounded b, Integral a, Integral b, Show a, Show b) =>
  String -> String -> a -> m b
safeCastIntegerlike destTypeName valueName x
  | toInteger x > toInteger (maxBound @b) =
      unexpected $
        "Resulting query has more "
          <> valueName
          <> " ("
          <> show x
          <> ") than max "
          <> destTypeName
          <> " ("
          <> show (maxBound @b)
          <> ") on the current architecture"
  | otherwise = pure $ toEnum $ fromEnum x

alloca' :: (Storable a) => (Ptr a -> QueryM b) -> QueryM b
alloca' cb =
  alloca (\ptr -> runExceptT $ cb ptr)
    & ExceptT
