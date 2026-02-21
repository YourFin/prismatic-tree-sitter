{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Query.RawSpec (spec) where

import Test.Hspec

import Control.Monad (forM_, void)
import Data.Function ((&))
import Data.Text (Text)
import Data.Vector qualified as Unsized
import Data.Vector.Sized qualified as Sized
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

--    describe "isPatternRooted should work" $ do
--      it "for a rooted pattern" $ \compile -> do
--        compiled <- compile "(number)"
--        SUT.isPatternRooted compiled 0 `shouldBe` True
--      it "for a non-rooted pattern" $ \compile -> do
--        compiled <- compile "((number) . (number))"
--        SUT.isPatternRooted compiled 0 `shouldBe` False
--
--    describe "isPatternNonLocal" $ do
--      it "for a local pattern" $ \compile -> do
--        compiled <- compile "(number)"
--        SUT.isPatternRooted compiled 0 `shouldBe` True
--      it "for a non-local pattern" $ \compile -> do
--        compiled <- compile "((number) . (number))"
--        SUT.isPatternRooted compiled 0 `shouldBe` False
--    describe "captureNames" $ do
--      it "should pull capture names" $ \compile -> do
--        compiled <-
--          compile
--            "((string . \"\\\"\" @quote . _ @contents) (#eq? @contents \"hello!\"))"
--        names <- parseRight $ SUT.captureNames compiled
--        names `shouldBe` ["quote", "contents"]

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
