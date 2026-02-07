{-# LANGUAGE CApiFFI #-}
{-# LANGUAGE UndecidableInstances #-}

module TreeSitter.Prismatic.Internal.Language.TH where

import Control.Monad.Writer.Strict (execWriter, tell)
import Data.Array (Array)
import Data.Array qualified as Array
import Data.Char (isAlpha, isControl, toUpper)
import Data.Functor ((<&>))
import Data.Ix (Ix)
import Foreign.C.ConstPtr (ConstPtr (..))
import Language.Haskell.TH (
  Dec,
  Exp,
  Name,
  Q,
  Quote (newName),
  cApi,
  conT,
  dataD,
  derivClause,
  forImpD,
  instanceD,
  litE,
  lookupValueName,
  mkName,
  nameBase,
  normalB,
  normalC,
  runIO,
  safe,
  sigD,
  stringL,
  valD,
  varE,
  varP,
 )

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Type.Equality (type (==))
import Language.Haskell.TH (integerL, listE)
import Language.Haskell.TH.Lib (varT)
import Language.Haskell.TH.Syntax (
  ForeignSrcLang (LangC),
  Quasi (qAddDependentFile, qAddForeignFilePath),
 )
import Language.Haskell.TH.Syntax qualified as TH
import TreeSitter.Prismatic.Internal.Binding (C'TSLanguage)
import TreeSitter.Prismatic.Internal.Language.Core
import TreeSitter.Prismatic.Internal.Language.Raw (RawLang)
import TreeSitter.Prismatic.Internal.Language.Raw qualified as Raw
import Type.Reflection (Typeable, someTypeRep, someTypeRepTyCon)

rawLanguageSplice :: [String] -> String -> String -> String -> Q [Dec]
rawLanguageSplice cFiles lang header cFunction = do
  assertValueImported 'ConstPtr
  forM_ cFiles (qAddForeignFilePath LangC) -- qAddDependentFile
  cImportName <- newName cFunction
  let langName = mkName lang
  sequenceA
    [ forImpD cApi safe (header <> " " <> cFunction) cImportName [t|IO (ConstPtr C'TSLanguage)|]
    , sigD langName [t|IO (String, RawLang)|]
    , valD
        (varP langName)
        ( normalB
            [e|($(litE (stringL lang)),) <$> Raw.mkLang $(varE cImportName)|]
        )
        []
    ]

stage2LanguageSplice :: Name -> IO (String, RawLang) -> Q [Dec]
stage2LanguageSplice rawIOName rawIO = do
  (name, rawLang) <- runIO $ rawIO
  let dataName = mkName (capitalize name)
  fields <- runIO $ Raw.langFields rawLang
  symbols <- runIO $ Raw.langSymbols rawLang
  libraryLangName <- runIO $ Raw.langName rawLang
  sequenceA
    [ dataD
        (pure [])
        dataName
        []
        Nothing
        [normalC dataName []]
        [derivClause Nothing [conT ''Eq]]
    , instanceD
        (pure [])
        [t|LangCore $(conT dataName)|]
        [ valD (varP 'langCoreRaw) (normalB [e|\_ -> $(varE rawIOName) <&> snd|]) []
        , valD (varP 'langCoreName) (normalB [e|\_ -> $(aLitE libraryLangName)|]) []
        , valD (varP 'langCoreFields) (normalB [e|\_ -> $(aLitE fields)|]) []
        , valD (varP 'langCoreSymbols) (normalB [e|\_ -> $(aLitE symbols)|]) []
        ]
    ]

capitalize :: String -> String
capitalize (c : cs) = toUpper c : cs
capitalize [] = []

assertValueImported :: Name -> Q ()
assertValueImported n =
  lookupValueName (nameBase n) >>= \case
    Just _ -> pure ()
    Nothing -> fail $ show n <> " must be added to the this module's imports"

-- | Convert haskell data type to equivalent literal expression
class AutoLit a where
  aLitE :: a -> Q Exp

instance AutoLit Text where
  aLitE txt = [e|Text.pack $(aLitE $ Text.unpack txt)|]

instance {-# OVERLAPPABLE #-} (Typeable a, Enum a) => AutoLit a where
  aLitE enum = [e|(toEnum $(litE $ integerL $ fromIntegral $ fromEnum enum))|]

instance (AutoLit a, AutoLit b) => AutoLit (a, b) where
  aLitE (a, b) = [e|($(aLitE a), $(aLitE b))|]

instance {-# OVERLAPS #-} AutoLit String where
  aLitE str = litE $ stringL $ str

instance (Typeable a, AutoLit a, (a == Char) ~ 'False) => AutoLit [a] where
  aLitE lst = listE $ (aLitE <$> lst)

instance (Typeable i, Typeable e, Ix i, AutoLit i, AutoLit e) => AutoLit (Array i e) where
  aLitE arr = [e|Array.array $(aLitE $ Array.bounds arr) $(aLitE $ Array.assocs arr)|]

-- smuggleTypeVar :: forall a. (Typeable a) => Proxy a -> Q TH.Type
-- smuggleTypeVar _ = do
--     let typeNameStr = tyConName $ someTypeRepTyCon $ someTypeRep (Proxy :: Proxy a)
--     mTypeName <- TH.lookupTypeName typeNameStr
--     typeName <- maybe (fail $ "Unable to find type " <> typeNameStr <> " in templated scope") pure mTypeName
--     TH.reifyType typeName
