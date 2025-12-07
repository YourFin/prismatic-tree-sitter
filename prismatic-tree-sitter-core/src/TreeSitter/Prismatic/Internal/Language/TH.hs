{-# LANGUAGE CApiFFI #-}

module TreeSitter.Prismatic.Internal.Language.TH where

import Data.Char (isAlpha, isControl, toUpper)
import Foreign.C.ConstPtr (ConstPtr (..))
import Language.Haskell.TH (
    Dec,
    Name,
    Q,
    Quote (newName),
    cApi,
    conT,
    dataD,
    derivClause,
    forImpD,
    lookupValueName,
    mkName,
    nameBase,
    normalB,
    normalC,
    safe,
    sigD,
    valD,
    varE,
    varP,
 )

import TreeSitter.Prismatic.Internal.Binding (C'TSLanguage)
import TreeSitter.Prismatic.Internal.Language (Lang, mkLang)

languageSplice :: String -> String -> String -> Q [Dec]
languageSplice lang header cFunction = do
    assertValueImported 'ConstPtr
    cImportName <- newName cFunction
    let langName = mkName lang
    let dataName = mkName (capitalize lang)
    sequenceA
        [ forImpD cApi safe (header <> " " <> cFunction) cImportName [t|IO (ConstPtr C'TSLanguage)|]
        , dataD (pure []) dataName [] Nothing [normalC dataName []] [derivClause Nothing [conT ''Eq]]
        , sigD langName [t|IO (Lang $(conT dataName))|]
        , valD
            (varP langName)
            ( normalB $
                [e|mkLang $(varE cImportName)|]
            )
            []
        ]

capitalize :: String -> String
capitalize (c : cs) = toUpper c : cs
capitalize [] = []

assertValueImported :: Name -> Q ()
assertValueImported n =
    lookupValueName (nameBase n) >>= \case
        Just _ -> pure ()
        Nothing -> fail $ show n <> " must be added to the this module's imports"
