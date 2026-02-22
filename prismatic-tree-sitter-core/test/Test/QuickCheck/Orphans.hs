module Test.QuickCheck.Orphans where

import Test.QuickCheck

import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty

instance (Arbitrary a) => Arbitrary (NonEmpty a) where
  arbitrary = do
    a <- arbitrary
    as <- arbitrary
    pure $ a :| as
