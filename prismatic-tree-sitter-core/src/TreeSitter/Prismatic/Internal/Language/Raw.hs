module TreeSitter.Prismatic.Internal.Language.Raw where

import Control.DeepSeq (NFData (..), rwhnf)
import Control.Monad (forM)
import Data.Array (Array)
import Data.Array qualified as Array
import Data.Function ((&))
import Data.Ix (Ix)
import Data.Kind (Type)
import Data.STRef (newSTRef)
import Data.Text (Text)
import Data.Text.Foreign qualified as Text
import Data.Word (Word16, Word32, Word8)
import Foreign (Storable (peek), alloca)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.C.Types (CUInt (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr, withForeignPtr)
import Foreign.Ptr (Ptr, nullPtr)
import GHC.Generics (Generic)
import TreeSitter.Prismatic.Internal.Binding
import TreeSitter.Prismatic.Internal.Language.LanguageAccessError
import TreeSitter.Prismatic.Internal.Language.SymbolType (SymbolType)
import TreeSitter.Prismatic.Internal.Language.SymbolType qualified as SymbolType

newtype RawLang = RawLang {unLang :: ForeignPtr C'TSLanguage}
  deriving (Eq, Ord)

instance NFData RawLang where
  rnf (RawLang lang) = rwhnf lang

mkLang :: IO (ConstPtr C'TSLanguage) -> IO RawLang
mkLang tree_sitter_lang = do
  (ConstPtr langPtr) <- tree_sitter_lang
  fptr <- newForeignPtr p'ts_language_delete_nonconst langPtr
  pure $ RawLang fptr

-- * Language properties; intended to be retrieved from template haskell

langName :: RawLang -> IO Text
langName (RawLang fp) = withForeignConstPtr fp $ \langPtr -> do
  let namePtr = unConstPtr $ c'ts_language_name langPtr
  if (namePtr == nullPtr)
    then
      langError "ts_language_name returned null pointer"
    else do
      Text.fromPtr0 namePtr

langSymbolCount :: RawLang -> IO Word16
langSymbolCount (RawLang fp) = withForeignConstPtr fp \ptr -> do
  let count = c'ts_language_symbol_count ptr
  if (count > (maxBound @Word16 & fromIntegral))
    then
      -- This covers for what appears to be a bug in the language interface
      langError
        ("More symbols reported (" <> show count <> ") than can be named in a tree sitter language")
    else
      pure (fromIntegral count)

langSymbolName :: RawLang -> Word16 -> IO Text
langSymbolName (RawLang fp) sym = withForeignConstPtr fp $ \ptr ->
  c'ts_language_symbol_name ptr sym
    & unConstPtr
    & Text.fromPtr0

langSymbolType :: RawLang -> Word16 -> IO SymbolType
langSymbolType (RawLang fp) sym = withForeignConstPtr fp $ \ptr ->
  SymbolType.fromCUInt
    ( c'ts_language_symbol_type ptr sym
        & fromEnum
        & toEnum
        & CUInt
    )

langSymbols :: RawLang -> IO (Array Word16 (SymbolType, Text))
langSymbols raw = do
  count <- langSymbolCount raw
  let range = (0, count - 1)
  symbols <- forM (uncurry enumFromTo range) $ \idx -> do
    name <- langSymbolName raw idx
    tipe <- langSymbolType raw idx
    pure (tipe, name)
  pure $ Array.listArray range symbols

langFieldCount :: RawLang -> IO Word16
langFieldCount (RawLang fp) = withForeignConstPtr fp \ptr -> do
  let count = c'ts_language_field_count ptr
  if (count > (maxBound @Word16 & fromIntegral))
    then
      -- This covers for what appears to be a bug in the language interface
      langError
        ("More fields reported (" <> show count <> ") than can be named in a tree sitter language")
    else
      pure (fromIntegral count)

langFieldName :: RawLang -> Word16 -> IO Text
langFieldName (RawLang fp) fieldId = withForeignConstPtr fp $ \ptr ->
  c'ts_language_field_name_for_id ptr fieldId
    & unConstPtr
    & Text.fromPtr0

langFields :: RawLang -> IO (Array Word16 Text)
langFields raw = do
  count <- langFieldCount raw
  let range = (1, count)
  fields <- forM (uncurry enumFromTo range) $ \idx ->
    langFieldName raw idx
  pure $ Array.listArray range fields

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)
