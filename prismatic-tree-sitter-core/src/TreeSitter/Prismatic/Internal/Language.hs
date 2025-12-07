module TreeSitter.Prismatic.Internal.Language where

import Data.Ix (Ix)
import Data.Kind (Type)
import Data.Text (Text)
import Data.Word (Word8)
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.ForeignPtr (ForeignPtr, newForeignPtr)
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

-- TODO: Enforce language names are valid
-- utf-8 in unit test
-- name :: Language -> Text
-- name l =
--    unlanguage l
--        & c'ts_language_name
--        & unConstPtr
