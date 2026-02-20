{-# LANGUAGE ImpredicativeTypes #-}
{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query.Raw where

import Prelude hiding (lines, tail)

import Control.Exception (Exception)
import Control.Exception qualified
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
import Control.Monad (forM, join, when)
import Control.Monad.Cont (ContT (ContT), cont, evalCont, evalContT)
import Control.Monad.Except (
  ExceptT (..),
  MonadError (throwError),
  runExceptT,
 )
import Control.Monad.IO.Class (liftIO)
import Data.Finite (Finite (..), packFinite)
import Data.Finite.Integral (finite, getFinite)
import Data.Vector qualified as Unsized
import Data.Vector.Sized (Vector)
import Data.Vector.Sized qualified as Sized
import Errata
import Errata.Styles qualified as Errata
import Foreign (Storable, alloca, nullPtr, peek)
import Foreign.C (CUInt (CUInt))
import Foreign.Marshal.Utils (toBool)
import Foreign.Ptr (Ptr)
import GHC.Generics (Generic)
import GHC.TypeLits (KnownNat, Nat)
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

data RawQuery patternCount captureCount
  = RawQuery
  { unQuery :: !(ForeignPtr C'TSQuery)
  , captureNames :: !(Vector captureCount Text)
  , predicates :: !(Vector patternCount [Predicate captureCount])
  , -- , captureQuantifiers :: Vector patternCount (Vector captureCount CaptureQuantifier)
    --
    -- , propertySettings :: Vector patternCount (Vector _ (QueryProperty captureCount))
    -- , propertyPredicates :: Vector patternCount (Vector _ (QueryProperty captureCount, Bool))
    -- , generalPredicates :: Vector patternCount (Vector _ (QueryPredicate captureCount))
    source :: !Text
  , -- Need to hold a handle on the raw language
    -- So the garbage collector doesn't kill it
    lang :: !RawLang
  }
  deriving (Eq, Ord, Generic)

-- type RawQuery =
--   forall (patternCount :: Nat) (captureCount :: Nat).
--   (KnownNat patternCount, KnownNat captureCount) => RawQuery' patternCount captureCount

{-| A key-value pair associated with a particular pattern in a [`Query`].
TODO: parse, don't validate?
-}
data QueryProperty captureCount = QueryProperty
  {key :: !Text, value :: !(Maybe Text), captureId :: !(Maybe (Finite captureCount))}
  deriving (Eq, Ord, Generic, Show)

data Predicate captureCount = Predicate {operator :: !Text, args :: ![PredicateArg captureCount]}
  deriving (Eq, Ord, Generic, Show)

data PredicateArg captureCount
  = PredicateArgCapture !(Finite captureCount)
  | PredicateArgString !Text
  deriving (Eq, Ord, Generic, Show)

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

unexpected :: (MonadError QueryError m) => String -> m a
unexpected = throwError . QueryErrorUnexpected

unknownEnumVal :: (MonadError QueryError m, Show a) => String -> a -> m b
unknownEnumVal enumName unknownValue =
  unexpected $
    "Got unknown value " <> show unknownValue <> " for the " <> enumName <> " enum"

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

withNew ::
  RawLang ->
  Text ->
  ( forall (p :: Nat) (c :: Nat).
    (KnownNat p, KnownNat c) => Either QueryError (RawQuery p c) -> r
  ) ->
  r
withNew lang query cb = cb $ unsafePerformIO $ (flip Control.Exception.catch) (pure . Left . QueryErrorIOException) $ evalCont do
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
        unQuery <- liftIO $ newForeignPtr p'ts_query_delete queryPtrMut

        let captureCountW32 = c'ts_query_capture_count queryPtr
        captureCount <- word32ToInt "capture count" captureCountW32
        captureNames' <- forM [0 .. captureCountW32 - 1] \capIdx ->
          alloca' $ \strLenPtr -> do
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
              ( \idx -> do
                  intIdx <- word32ToInt "string literal index" idx
                  case (stringLiterals Unsized.!? intIdx) of
                    (Just str) -> pure str
                    Nothing ->
                      unexpected $
                        "Requested string literal #"
                          <> show intIdx
                          <> ( case Unsized.length stringLiterals of
                                 0 -> "; when query contained none"
                                 len -> ", max is " <> (show (len - 1))
                             )
              ) ::
                Word32 -> QueryM Text

        patternCount <- c'ts_query_pattern_count queryPtr & word32ToInt "pattern count"

        Sized.withSizedList captureNames' $ \captureNames -> do
          unsizedPreds <- Unsized.generateM patternCount $ \patIdx' -> do
            rawPredSteps <- alloca' $ \stepCountPtr -> do
              patIdx <- intToWord32 "pattern index" patIdx'
              predsPtr <- liftIO $ c'ts_query_predicates_for_pattern queryPtr patIdx stepCountPtr
              stepCount <- (liftIO . peek) stepCountPtr >>= word32ToInt "predicate steps"
              if stepCount == 0
                then
                  pure []
                else do
                  liftIO $ peekConstArray stepCount predsPtr

            rawPredSteps
              & splitOn ((c'TSQueryPredicateStepTypeDone ==) . c'TSQueryPredicateStep'type)
              & traverse \case
                [] -> pure Nothing
                ((StringStep operatorId) : argSteps) -> do
                  operator <- stringLitByIdx operatorId
                  args <- forM argSteps $ \case
                    (StringStep id) -> do
                      name <- stringLitByIdx id
                      pure $ PredicateArgString name
                    (CaptureStep idx) -> case packFinite (toInteger idx) of
                      Just finiteIdx ->
                        pure $ PredicateArgCapture finiteIdx
                      Nothing ->
                        unexpected $
                          "Predicate contained reference to capture #"
                            <> show idx
                            <> ( case captureCount of
                                   0 -> "; query has no captures"
                                   _ -> ", max is " <> show (captureCount - 1)
                               )
                    (C'TSQueryPredicateStep{..}) ->
                      unexpected $
                        "Unexpected query predicate step type "
                          <> show c'TSQueryPredicateStep'type
                          <> "; expected type String ("
                          <> show (c'TSQueryPredicateStepTypeString @Int)
                          <> ") or Capture ("
                          <> show (c'TSQueryPredicateStepTypeCapture @Int)
                          <> ")"
                  pure $ Just Predicate{..}
                (C'TSQueryPredicateStep{..} : _) ->
                  unexpected $
                    "Unexpected query predicate step type "
                      <> show c'TSQueryPredicateStep'type
                      <> "; expected type String ("
                      <> show (c'TSQueryPredicateStepTypeString @Int)
                      <> ")"
              <&> catMaybes
          -- end unsizedPreds
          pure $ Sized.withSized unsizedPreds $ \predicates ->
            RawQuery{source = query, ..}

-- TODO: audit unexpected messagses for consistency
splitOn :: (a -> Bool) -> [a] -> [[a]]
splitOn pred = foldl' f []
 where
  f acc a = case (acc, pred a) of
    (_, True) -> [] : acc
    ([], False) -> [[a]]
    (cur : rest, _) -> (a : cur) : rest

pattern FiniteWord32 :: Word32 -> Finite n
pattern FiniteWord32 x <- (fromInteger . getFinite -> x)

pattern StringStep :: Word32 -> C'TSQueryPredicateStep
pattern StringStep valueId <-
  C'TSQueryPredicateStep ((== c'TSQueryPredicateStepTypeString) -> True) valueId

pattern CaptureStep :: Word32 -> C'TSQueryPredicateStep
pattern CaptureStep valueId <-
  C'TSQueryPredicateStep ((== c'TSQueryPredicateStepTypeCapture) -> True) valueId

-- patternCount :: RawQuery -> Word32
-- patternCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_pattern_count
--
-- captureCount :: RawQuery -> Word32
-- captureCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_capture_count
--
-- stringLiteralCount :: RawQuery -> Word32
-- stringLiteralCount = flip withQueryPtrReferentiallyTransparent $ c'ts_query_string_count

-- -- | Check if the given pattern in the query has a single root node.
-- isPatternRooted :: RawQuery -> Word32 -> Bool
-- isPatternRooted query patternIdx = withQueryPtrReferentiallyTransparent query $ \queryPtr ->
--   c'ts_query_is_pattern_rooted queryPtr patternIdx
--     & toBool
-- {-# WARNING in "x-partial" isPatternRooted "pattern index argument can go out of bounds and read arbitrary memory" #-}
--
-- {-| Check if the given pattern in the query is 'non local'.
--
--   A non-local pattern has multiple root nodes and can match within a
--   repeating sequence of nodes, as specified by the grammar. Non-local
--   patterns disable certain optimizations that would otherwise be possible
--   when executing a query on a specific range of a syntax tree.
-- -}
-- isPatternNonLocal :: RawQuery -> Word32 -> Bool
-- isPatternNonLocal query patternIdx = withQueryPtrReferentiallyTransparent query $ \queryPtr ->
--   c'ts_query_is_pattern_non_local queryPtr patternIdx
--     & toBool
-- {-# WARNING in "x-partial" isPatternNonLocal "pattern index argument can go out of bounds and read arbitrary memory" #-}

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

-- predicatesForPattern :: RawQuery -> Word32 -> [C'TSQueryPredicateStep]
-- predicatesForPattern query patternIdx = unsafePerformIO $ withQueryPtrReferentiallyTransparent query $ \queryPtr ->
--   alloca $ \stepCountOut -> do
--     arrPtr <- c'ts_query_predicates_for_pattern queryPtr patternIdx stepCountOut
--     stepCount <- peek stepCountOut
--     when (toInteger stepCount > toInteger (maxBound :: Int)) $
--       fail
--         ( "Query predicate steps ("
--             <> show stepCount
--             <> ") greater than max : "
--             <> show (maxBound :: Int)
--         )
--     peekConstArray (fromEnum stepCount) arrPtr
-- {-# WARNING in "x-partial"
--   predicatesForPattern
--   "pattern index argument can go out of bounds and read arbitrary memory"
--   #-}

{-| Get the name and length of one of the query's captures, or one of the
  query's string literals. Each capture and string is associated with a
  numeric id based on the order that it appeared in the query's source.

  Port of ts_query_capture_name_for_id, which appears to have taken on the
  string-literal fetching functionality later in life.
-}

-- captureNames :: (MonadError QueryError m) => RawQuery -> m [Text]
-- captureNames query = unsafePerformIO_queryError $ withQueryPtrReferentiallyTransparent query $ \queryPtr -> do
--   let capCount = captureCount query
--   forM [0 .. capCount - 1] \capIdx ->
--     alloca' $ \strLenPtr -> do
--       (ConstPtr strPtr) <- liftIO $ c'ts_query_capture_name_for_id queryPtr capIdx strLenPtr
--       strLen' <- liftIO $ peek strLenPtr
--       strLen <- word32ToInt "capture name length" strLen'
--       bytes <- liftIO $ ByteString.packCStringLen (strPtr, fromEnum strLen)
--       pure $ Text.decodeUtf8Lenient bytes

-- queryStringValueForId :: RawQuery -> Word32 -> Text
-- queryStringValueForId query predicateIdx = unsafePerformIO $ withQueryPtrReferentiallyTransparent query $ \queryPtr ->
--   alloca $ \strLenPtr -> do
--     (ConstPtr strPtr) <- c'ts_query_capture_name_for_id queryPtr predicateIdx strLenPtr
--     strLen <- peek strLenPtr
--     when (toInteger strLen > toInteger (maxBound :: Int)) $
--       fail
--         ( "Query capture has length ("
--             <> show strLen
--             <> "), greater than IntMax: "
--             <> show (maxBound :: Int)
--         )
--     bytes <- ByteString.packCStringLen (strPtr, fromEnum strLen)
--     pure $ Text.decodeUtf8Lenient bytes

{-| UNSAFE - helper method for writing accessor methods against queries.
must not have side effects.
-}

-- withQueryPtrReferentiallyTransparent :: RawQuery -> (ConstPtr C'TSQuery -> a) -> a
-- withQueryPtrReferentiallyTransparent query closure =
--   unsafePerformIO $ withForeignConstPtr (unQuery query) $ \ptr -> pure $ closure ptr

unsafePerformIO_queryError :: (MonadError QueryError m) => QueryM a -> m a
unsafePerformIO_queryError ma = case unsafePerformIO $ runExceptT ma of
  Right a -> pure a
  Left e -> throwError e

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
        "resulting query has more "
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
