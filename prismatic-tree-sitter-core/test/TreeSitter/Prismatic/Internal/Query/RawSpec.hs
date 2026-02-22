{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query.RawSpec (spec) where

import Prettyprinter.Render.String qualified as Pretty
import Prettyprinter.Render.Text qualified as Pretty
import Test.Hspec
import Test.QuickCheck
import Test.QuickCheck qualified as QuickCheck
import Test.QuickCheck.Orphans

import Control.Monad (forM_, void)
import Data.Function ((&))
import Data.Functor (($>), (<&>))
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Vector qualified as Unsized
import Data.Vector.Sized qualified as Sized
import GHC.Generics (Generic)
import Generic.Random
import Generic.Random (genericArbitrary)
import Prettyprinter
import Prettyprinter (layoutSmart)
import Test.QuickCheck (Arbitrary (arbitrary))
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Query.Raw qualified as SUT
import TreeSitter.Prismatic.Language.Json.Raw (withJsonRawLang)

spec :: Spec
spec = do
  describe "new" do
    around withJsonRawLang $ do
      it "simple creation succeeds" $ \json -> do
        SUT.new json "(number)" & shouldBeRight
      it "should return an error for when missing a paren" $ \json -> do
        SUT.new json "(number" & shouldBeLeft
      it "should return an error for when node type doesn't exist" $ \json -> do
        SUT.new json "(totallyAKindOfJsonNode)" & shouldBeLeft

    around withCompileJson $ do
      describe "should accurately report pattern count" $
        forM_ [(1, "(number)"), (2, "(number) (string)")] $
          \(expected, query) -> it ("for query: " <> show query) $ \compile -> do
            (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile query
            Unsized.length patterns `shouldBe` expected

      describe "should accurately report capture count"
        $ forM_
          [ (["a"], "(array (number) @a)")
          , (["a", "b"], "(array (number) @a (number) @b)")
          , (["a", "b"], "(array (string) @a) (array (object) @b)")
          ]
        $ \(expected, query) -> it ("for pattern: " <> show query) $ \compile -> do
          (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile query
          Sized.toList captureNames `shouldBe` expected

      it "should populate a non-empty predicates list" $ \compile -> do
        (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile "((array _ @a _ @b) (#eq? @a @b))"
        SUT.Pattern{..} <- parseHead patterns
        statements `shouldSatisfy` ((/= 0) . length)

      it "should parse a bunch o' patterns" $ \compile -> do
        (SUT.RawQuery _ SUT.RawQuery'{..}) <-
          compile $
            "((array _ @a _ @b) (#eq? @a @b))" <> "((number) @i (#set! j \"1\") (#eq? @i \"1\"))"
        patterns `shouldSatisfy` ((== 2) . length)
      describe "should read locality correctly" $ do
        it "for a rooted pattern" $ \compile -> do
          (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile "(number)"
          SUT.Pattern{..} <- parseHead patterns
          locality `shouldBe` SUT.SingleRootPattern
        it "for a local pattern" $ \compile -> do
          (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile "(number)+"
          SUT.Pattern{..} <- parseHead patterns
          locality `shouldBe` SUT.LocalPattern
        describe "for non-local pattern"
          $ forM_
            [ "((number)+)"
            , "((number) (number))"
            , "((number) . (number))"
            , "(array . (number)+ .)"
            , "(. (number) . (number) .)"
            ]
          $ \query -> it (show query) \compile -> do
            (SUT.RawQuery _ SUT.RawQuery'{..}) <- compile "((number) . (number))"
            Unsized.length patterns `shouldBe` 1
            SUT.Pattern{..} <- parseHead patterns
            locality `shouldBe` SUT.NonLocalPattern

      it "should pull capture names" $ \compile -> do
        (SUT.RawQuery _ SUT.RawQuery'{..}) <-
          compile
            "((string . \"\\\"\" @quote . _ @contents) (#eq? @contents \"hello!\"))"
        (Sized.toList captureNames) `shouldBe` ["quote", "contents"]

      it "parses generated queries" $ \compile -> forallJsonExpr $ \expr -> do
        _ <- compile expr
        pure ()

withCompileJson :: ((Text -> IO SUT.RawQuery) -> IO ()) -> IO ()
withCompileJson action = withJsonRawLang $ \json -> do
  let compile = \query -> SUT.new json query & parseRight
  action compile

--- Helpers that don't require show

parseRight :: (Show e) => Either e a -> IO a
parseRight (Left e) = do
  expectationFailure $ "Expected Right; got Left (" <> show e <> ")"
  pure undefined
parseRight (Right a) = pure a

parseHead :: Unsized.Vector a -> IO a
parseHead (Unsized.toList -> []) = do
  expectationFailure $ "expected non-empty list"
  pure undefined
parseHead (Unsized.toList -> (a : _)) = pure a

shouldBeRight :: (Show e) => Either e a -> Expectation
shouldBeRight x = void $ parseRight x

shouldBeLeft :: Either e a -> Expectation
shouldBeLeft (Right _) = expectationFailure $ "Expected Left; got Right"
shouldBeLeft (Left _) = pure ()

forallJsonExpr :: (Testable prop) => (Text -> prop) -> Property
forallJsonExpr cb =
  forAllShow
    (arbitrary @ArbJsonQueryExpr)
    (Pretty.renderString . (layoutSmart defaultLayoutOptions) . pretty)
    (cb . Pretty.renderStrict . layoutCompact . pretty)

type ArbJsonQueryExpr = Capturable (Wildcarded ArbJsonQueryExpr')

data ArbJsonQueryExpr'
  = TrueExpr
  | NullExpr
  | NumberExpr
  | StringExpr
  | WildcardNamedExpr
  | WildcardUnnamedExpr
  | ErrorNodeExpr
  | MissingNodeExpr
  | OneOfExpr (NonEmpty ArbJsonQueryExpr)
  | ArrayExpr (DotList ArbJsonQueryExpr)
  | ObjectExpr (DotList (Wildcarded ((Capturable ()), ArbJsonQueryExpr)))
  deriving (Eq, Ord, Generic)

instance Pretty ArbJsonQueryExpr' where
  pretty TrueExpr = pt "(true)"
  pretty NullExpr = pt "(null)"
  pretty NumberExpr = pt "(number)"
  pretty StringExpr = pt "(string)"
  pretty WildcardNamedExpr = pt "(_)"
  pretty WildcardUnnamedExpr = "_"
  pretty ErrorNodeExpr = pt "(ERROR)"
  pretty MissingNodeExpr = pt "(MISSING)"
  pretty (OneOfExpr exprs) = brackets $ nest 2 $ sep $ pretty <$> (NonEmpty.toList exprs)
  pretty (ArrayExpr exprs) = sexp "array" $ unDotList exprs
  pretty (ObjectExpr (DotList kvs)) =
    sexp "object" $
      kvs <&> (fmap . fmap) \(k, v) ->
        AnyDoc $ sexp "pair" $ [anyDoc (k $> StringExpr), anyDoc v]

instance Arbitrary ArbJsonQueryExpr' where
  arbitrary =
    genericArbitrary uniform
      `withBaseCase` (pure NullExpr)
      & scale (`div` 2)

sexp :: (Pretty a) => Text -> [a] -> Doc ann
sexp name args = parens $ pt name <> space <> (nest 2 $ sep $ pretty <$> args)

data Wildcarded a
  = NoWildcard a
  | ManyPlus a
  | ManyStar a
  deriving (Eq, Ord, Generic, Functor)

instance (Pretty a) => Pretty (Wildcarded a) where
  pretty = \case
    (NoWildcard a) -> pretty a
    (ManyPlus a) -> pretty a <> pt "+"
    (ManyStar a) -> pretty a <> pt "*"

instance (Arbitrary a) => Arbitrary (Wildcarded a) where
  arbitrary =
    genericArbitrary (90 % 5 % 5 % ())
      & scale (`div` 2)

data Capturable a
  = Uncaptured a
  | Captured CaptureName a
  deriving (Eq, Ord, Generic, Functor)

newtype CaptureName = CaptureName Text
  deriving stock (Generic)
  deriving newtype (Eq, Ord, Show)

instance Arbitrary CaptureName where
  arbitrary =
    CaptureName
      <$> elements
        [ "alpha"
        , "beta"
        , "gamma"
        , "delta"
        , "epsilon"
        , "theta"
        ]

instance (Pretty a) => Pretty (Capturable a) where
  pretty (Uncaptured a) = pretty a
  pretty (Captured (CaptureName name) a) = pretty a <> space <> pt "@" <> pretty name

instance (Arbitrary a) => Arbitrary (Capturable a) where
  arbitrary =
    genericArbitrary (95 % 5 % ())
      & scale (`div` 2)

instance (Pretty a, Pretty b) => Pretty (EitherP a b) where
  pretty (EitherP (Left a)) = pretty a
  pretty (EitherP (Right b)) = pretty b

newtype DotList a = DotList {unDotList :: [EitherP Dot a]}
  deriving (Eq, Ord, Generic, Functor)

instance (Pretty a) => Pretty (DotList a) where
  pretty (DotList lst) = sep (pretty <$> lst)

instance (Arbitrary a) => Arbitrary (DotList a) where
  arbitrary = do
    concentration <- chooseInt (1, fidelity)
    values <- (arbitrary :: Gen [a])
    if length values == 0
      then
        pure $ DotList []
      else
        values
          & fmap (pure . Just . EitherP . Right)
          & go (mkGenDot concentration)
          & sequenceA
          <&> catMaybes
          <&> DotList
   where
    fidelity = 10000
    mkGenDot concentration =
      chooseInt (1, fidelity)
        <&> ( \r ->
                if r < concentration
                  then
                    Just $ EitherP $ Left $ Dot
                  else
                    Nothing
            )
    go genDot [] = [genDot]
    go genDot (a : as) = genDot : a : go genDot as

data Dot = Dot
  deriving (Eq, Ord, Generic)

instance Pretty Dot where
  pretty Dot = pt "."

newtype EitherP a b = EitherP {unEitherP :: Either a b}
  deriving stock (Generic)
  deriving newtype (Eq, Ord, Show, Functor)
data AnyDoc where
  AnyDoc :: (forall ann. Doc ann) -> AnyDoc

anyDoc :: (Pretty a) => a -> AnyDoc
anyDoc a = AnyDoc $ pretty a

instance Pretty AnyDoc where
  pretty (AnyDoc a) = a

pt :: Text -> Doc ann
pt = pretty
