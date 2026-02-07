module TreeSitter.Prismatic.Internal.Foreign.Array where

import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable

{-| Convert an array of given length into a Haskell list.  The implementation
 is tail-recursive and so uses constant stack space.
-}
peekConstArray :: (Storable a) => Int -> ConstPtr a -> IO [a]
{-# INLINEABLE peekConstArray #-}
peekConstArray size (ConstPtr ptr) = peekArray size ptr
