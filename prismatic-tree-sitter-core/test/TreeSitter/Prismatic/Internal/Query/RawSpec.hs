{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query.RawSpec (spec) where

import Control.Monad (forM_, void)
import Data.Function ((&))
import Test.Hspec

import Data.Text (Text)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Query.Raw qualified as SUT
import TreeSitter.Prismatic.Language.Json.Raw (withJsonRawLang)

spec :: Spec
spec = do
  around withJsonRawLang $ do
    describe "new" do
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
          compiled <- compile query
          SUT.patternCount compiled `shouldBe` expected
    describe "should accurately report capture count"
      $ forM_
        [ (1, "(array (number) @a)")
        , (2, "(array (number) @a (number) @b)")
        , (2, "(array (string) @a) (array (object) @b)")
        ]
      $ \(expected, query) -> it ("for pattern: " <> show query) $ \compile -> do
        compiled <- compile query
        SUT.captureCount compiled `shouldBe` expected
    it "predicatesForPattern should populate a non-empty predicates list" $ \compile -> do
      compiled <- compile "((array _ @a _ @b) (#eq? @a @b))"
      SUT.predicatesForPattern compiled 0 `shouldSatisfy` ((/= 0) . length)
    describe "isPatternRooted should work" $ do
      it "for a rooted pattern" $ \compile -> do
        compiled <- compile "(number)"
        SUT.isPatternRooted compiled 0 `shouldBe` True
      it "for a non-rooted pattern" $ \compile -> do
        compiled <- compile "((number) . (number))"
        SUT.isPatternRooted compiled 0 `shouldBe` False

    describe "isPatternNonLocal" $ do
      it "for a local pattern" $ \compile -> do
        compiled <- compile "(number)"
        SUT.isPatternRooted compiled 0 `shouldBe` True
      it "for a non-local pattern" $ \compile -> do
        compiled <- compile "((number) . (number))"
        SUT.isPatternRooted compiled 0 `shouldBe` False
    describe "captureNames" $ do
      it "should pull capture names" $ \compile -> do
        compiled <-
          compile
            "((string . \"\\\"\" @quote . _ @contents) (#eq? @contents \"hello!\"))"
        names <- parseRight $ SUT.captureNames compiled
        names `shouldBe` ["quote", "contents"]

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

shouldBeRight :: (Show e) => Either e a -> Expectation
shouldBeRight x = void $ parseRight x

shouldBeLeft :: Either e a -> Expectation
shouldBeLeft (Right _) = expectationFailure $ "Expected Left; got Right"
shouldBeLeft (Left _) = pure ()
