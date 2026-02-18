{-# LANGUAGE OverloadedStrings #-}

module TreeSitter.Prismatic.Internal.Tree where

import Control.Monad.ST (ST)
import Control.Monad.ST.Unsafe (unsafeIOToST)
import Data.Word (Word32)
import Foreign (Storable (peek, poke), alloca)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr, withForeignPtr)
import Foreign.Ptr (nullPtr)
import GHC.Generics (Generic)
import System.IO.Unsafe (unsafePerformIO)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Foreign.Array (peekConstArray)
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang (..))

-- | An immutable syntax tree.
data RawTree = RawTree
  { unTree :: !(ForeignPtr C'TSTree)
  , -- Need to hold a handle on the raw language
    -- So the garbage collector doesn't kill it
    lang :: !RawLang
  }
  deriving (Eq, Ord, Generic)

-- | A mutable syntax tree with a phantom type parameter 's' for ST-style mutation tracking.
-- The type parameter ensures that mutable trees cannot escape their ST context.
-- This is LLM generated - TODO: validate that this is a sensible use of ST
-- https://web.archive.org/web/20130520095341/https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.50.3299&rep=rep1&type=pdf
data MRawTree s = MRawTree
  { mUnTree :: !(ForeignPtr C'TSTree)
  , mLang :: !RawLang
  }
  deriving (Generic)
type role MRawTree nominal

-- | Typeclass for operations that work on both mutable and immutable trees.
class TreeLike tree where
  -- | Get the root node of the syntax tree.
  rootNode :: tree -> C'TSNode
  
  -- | Get the root node of the syntax tree, but with its position shifted forward by the given offset.
  rootNodeWithOffset :: tree -> Word32 -> C'TSPoint -> C'TSNode
  
  -- | Get the language that was used to parse the syntax tree.
  language :: tree -> RawLang
  
  -- | Get the array of included ranges that was used to parse the syntax tree.
  includedRanges :: tree -> IO [C'TSRange]

-- | Internal typeclass for accessing the underlying ForeignPtr.
-- This is not exported and only used for sharing implementation.
class TreePtr tree where
  getTreePtr :: tree -> ForeignPtr C'TSTree

instance TreePtr RawTree where
  getTreePtr = unTree

instance TreePtr (MRawTree s) where
  getTreePtr = mUnTree

instance TreeLike RawTree where
  rootNode = rootNodeImpl
  rootNodeWithOffset = rootNodeWithOffsetImpl
  language = lang
  includedRanges = includedRangesImpl

instance TreeLike (MRawTree s) where
  rootNode = rootNodeImpl
  rootNodeWithOffset = rootNodeWithOffsetImpl
  language = mLang
  includedRanges = includedRangesImpl

-- * Operations on mutable trees

-- | Create a shallow copy of a mutable tree in the ST monad.
-- The copy gets a fresh type parameter, allowing it to be used in a different ST context.
copyM :: MRawTree s -> ST s' (MRawTree s')
copyM (MRawTree fp lang) = unsafeIOToST $ withForeignConstPtr fp $ \treePtr -> do
  newTreePtr <- c'ts_tree_copy treePtr
  if newTreePtr == nullPtr
    then error "ts_tree_copy returned null pointer"
    else do
      mUnTree <- newForeignPtr p'ts_tree_delete newTreePtr
      pure $ MRawTree{mUnTree, mLang = lang}

-- | Edit the syntax tree to keep it in sync with source code that has been edited.
-- This mutates the tree in place within the ST monad.
edit :: MRawTree s -> C'TSInputEdit -> ST s ()
edit (MRawTree{mUnTree}) inputEdit = unsafeIOToST $ withForeignPtr mUnTree $ \treePtr ->
  alloca $ \editPtr -> do
    poke editPtr inputEdit
    c'ts_tree_edit treePtr (ConstPtr editPtr)

-- * Freeze and thaw operations

-- | Freeze a mutable tree, making it immutable.
-- This creates a copy to ensure the original mutable tree can still be modified.
freeze :: MRawTree s -> ST s RawTree
freeze (MRawTree fp lang) = unsafeIOToST $ withForeignConstPtr fp $ \treePtr -> do
  newTreePtr <- c'ts_tree_copy treePtr
  if newTreePtr == nullPtr
    then error "ts_tree_copy returned null pointer (freeze)"
    else do
      unTree <- newForeignPtr p'ts_tree_delete newTreePtr
      pure $ RawTree{unTree, lang}

-- | Thaw an immutable tree, making it mutable in a new ST context.
-- This creates a copy to ensure the original immutable tree remains unchanged.
thaw :: RawTree -> ST s (MRawTree s)
thaw (RawTree fp lang) = unsafeIOToST $ withForeignConstPtr fp $ \treePtr -> do
  newTreePtr <- c'ts_tree_copy treePtr
  if newTreePtr == nullPtr
    then error "ts_tree_copy returned null pointer (thaw)"
    else do
      mUnTree <- newForeignPtr p'ts_tree_delete newTreePtr
      pure $ MRawTree{mUnTree, mLang = lang}

-- | Unsafely freeze a mutable tree without copying.
-- This is unsafe because the mutable tree should not be used after freezing.
unsafeFreeze :: MRawTree s -> ST s RawTree
unsafeFreeze (MRawTree fp lang) = pure $ RawTree fp lang

-- | Unsafely thaw an immutable tree without copying.
-- This is unsafe because the immutable tree should not be used after thawing.
unsafeThaw :: RawTree -> ST s (MRawTree s)
unsafeThaw (RawTree fp lang) = pure $ MRawTree fp lang

-- * Shared implementation helpers

-- | Internal helper for rootNode implementation.
rootNodeImpl :: TreePtr tree => tree -> C'TSNode
rootNodeImpl tree = unsafePerformIO $ withForeignConstPtr (getTreePtr tree) $ \treePtr ->
  alloca $ \nodePtr -> do
    c'ts_tree_root_node_ treePtr nodePtr
    peek nodePtr

-- | Internal helper for rootNodeWithOffset implementation.
rootNodeWithOffsetImpl :: TreePtr tree => tree -> Word32 -> C'TSPoint -> C'TSNode
rootNodeWithOffsetImpl tree offsetBytes offsetExtent = unsafePerformIO $ 
  withForeignConstPtr (getTreePtr tree) $ \treePtr ->
    alloca $ \nodePtr ->
      alloca $ \pointPtr -> do
        poke pointPtr offsetExtent
        c'ts_tree_root_node_with_offset_ treePtr offsetBytes pointPtr nodePtr
        peek nodePtr

-- | Internal helper for includedRanges implementation.
includedRangesImpl :: TreePtr tree => tree -> IO [C'TSRange]
includedRangesImpl tree = withForeignConstPtr (getTreePtr tree) $ \treePtr ->
  alloca $ \lengthPtr -> do
    rangesPtr <- c'ts_tree_included_ranges treePtr lengthPtr
    len <- peek lengthPtr
    if rangesPtr == nullPtr
      then pure []
      else do
        ranges <- peekConstArray (fromIntegral len) (ConstPtr rangesPtr)
        c_free rangesPtr
        pure ranges

-- | Compare an old edited syntax tree to a new syntax tree representing the same document.
-- Returns the ranges of text that changed.
-- This works on any combination of mutable and immutable trees.
getChangedRanges :: (TreePtr tree1, TreePtr tree2) => tree1 -> tree2 -> IO [C'TSRange]
getChangedRanges oldTree newTree =
  withForeignConstPtr (getTreePtr oldTree) $ \oldTreePtr ->
    withForeignConstPtr (getTreePtr newTree) $ \newTreePtr ->
      alloca $ \lengthPtr -> do
        rangesPtr <- c'ts_tree_get_changed_ranges oldTreePtr newTreePtr lengthPtr
        len <- peek lengthPtr
        if rangesPtr == nullPtr
          then pure []
          else do
            ranges <- peekConstArray (fromIntegral len) (ConstPtr rangesPtr)
            c_free rangesPtr
            pure ranges

-- * Helper functions

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)
