module TreeSitter.Prismatic.Internal.Language where

import Control.Exception (Exception, throwIO)
import Data.Function ((&))
import Data.Ix (Ix)
import Data.Kind (Type)
import Data.STRef (newSTRef)
import Data.Text (Text)
import Data.Text.Foreign qualified as Text
import Data.Word (Word16, Word32, Word8)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr, withForeignPtr)
import Foreign.Ptr (Ptr, nullPtr)
import GHC.Generics (Generic)
import TreeSitter.Prismatic.Internal.Binding

data SymbolType = Regular | Anonymous | Auxiliary
    deriving (Eq, Ord, Enum, Generic)

class (Bounded a, Enum a, Show a, Ix a) => Symbol a where
    symbolType :: a -> SymbolType
    symbolName :: a -> Text

type FieldId a = Symbol a

class (Symbol (LanguageSymbol a), FieldId (LanguageFieldId a)) => Language a where
    type LanguageSymbol a :: Type
    type LanguageFieldId a :: Type
    treeSitterLanguage :: a -> IO (Lang a)
    languageName :: a -> Text
    languageVersion :: a -> LangVersion

newtype Lang a = Lang {unLang :: ForeignPtr C'TSLanguage}
    deriving (Eq)

mkLang :: IO (ConstPtr C'TSLanguage) -> IO (Lang a)
mkLang tree_sitter_lang = do
    (ConstPtr langPtr) <- tree_sitter_lang
    fptr <- newForeignPtr p'ts_language_delete_nonconst langPtr
    pure $ Lang fptr

-- data Language = Language
--    { ptr :: ConstPtr C'TSLanguage
--    , name :: Text
--    , version :: LangVersion
--    }
--    deriving (Eq)

data LangVersion = LangVersion
    { major :: Word8
    , minor :: Word8
    , patch :: Word8
    }
    deriving (Eq, Ord, Show, Generic)

-- * Language properties; intended to be retrieved from template haskell

langName :: Lang a -> IO Text
langName (Lang fp) = withForeignConstPtr fp $ \langPtr -> do
    let namePtr = unConstPtr $ c'ts_language_name langPtr
    if (namePtr == nullPtr)
        then
            langError "ts_language_name returned null pointer"
        else do
            Text.fromPtr0 namePtr

langSymbolCount :: Lang a -> IO Word16
langSymbolCount (Lang fp) = withForeignConstPtr fp \ptr -> do
    let count = c'ts_language_symbol_count ptr
    if (count > (maxBound @Word16 & fromIntegral))
        then
            -- This covers for what appears to be a bug in the language interface
            langError ("More symbols reported (" <> show count <> ") than can be named in a tree sitter language")
        else
            pure (fromIntegral count)

langSymbolName :: Lang a -> Word16 -> IO Text
langSymbolName (Lang fp) sym = withForeignConstPtr fp $ \ptr ->
    c'ts_language_symbol_name ptr sym
        & unConstPtr
        & Text.fromPtr0

langFieldCount :: Lang a -> IO Word16
langFieldCount (Lang fp) = withForeignConstPtr fp \ptr -> do
    let count = c'ts_language_field_count ptr
    if (count > (maxBound @Word16 & fromIntegral))
        then
            -- This covers for what appears to be a bug in the language interface
            langError ("More fields reported (" <> show count <> ") than can be named in a tree sitter language")
        else
            pure (fromIntegral count)

langFieldName :: Lang a -> Word16 -> IO Text
langFieldName (Lang fp) fieldId = withForeignConstPtr fp $ \ptr ->
    c'ts_language_field_name_for_id ptr fieldId
        & unConstPtr
        & Text.fromPtr0

newtype TreesitterLanguageAccessError = TreesitterLanguageAccessError String
    deriving stock (Show)

instance Exception TreesitterLanguageAccessError

langError :: String -> IO a
langError = throwIO . TreesitterLanguageAccessError

withForeignConstPtr :: ForeignPtr a -> (ConstPtr a -> IO b) -> IO b
withForeignConstPtr fp closure = withForeignPtr fp $ \ptr -> closure (ConstPtr ptr)
