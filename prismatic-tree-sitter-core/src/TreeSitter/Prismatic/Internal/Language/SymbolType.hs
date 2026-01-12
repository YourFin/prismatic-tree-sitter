{-
 Intended for qualified import
-}
module TreeSitter.Prismatic.Internal.Language.SymbolType where

import Foreign.C.Types (CUInt)
import GHC.Generics (Generic)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Language.LanguageAccessError

data SymbolType
    = Regular
    | Anonymous
    | Supertype
    | Auxiliary
    deriving stock (Eq, Ord, Show, Generic, Enum)

{- | Takes the direct output of `c'ts_language_symbol_type` and converts
  to a `SymbolType`.
  Done in `IO` to allow for newer ABI versions that report new symbol types;
  in which case this will throw an exception
-}
fromCUInt :: CUInt -> IO SymbolType
fromCUInt uintSym =
    case uintSym of
        c'TSSymbolTypeRegular -> pure Regular
        c'TSSymbolTypeAnonymous -> pure Anonymous
        c'TSSymbolTypeSupertype -> pure Supertype
        c'TSSymbolTypeAuxiliary -> pure Auxiliary
        unknown -> langError $ "Raw symbol type enum " <> show unknown <> " received from tree-sitter c library out of known range. This is likely the result of the symbols being received from a newer tree-sitter ABI than this library knows how to handle."
