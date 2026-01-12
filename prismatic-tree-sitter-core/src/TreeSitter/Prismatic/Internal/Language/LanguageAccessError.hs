module TreeSitter.Prismatic.Internal.Language.LanguageAccessError where

import Control.Exception (Exception, throwIO)

newtype TreesitterLanguageAccessError = TreesitterLanguageAccessError String
    deriving stock (Show)

instance Exception TreesitterLanguageAccessError

langError :: String -> IO a
langError = throwIO . TreesitterLanguageAccessError
