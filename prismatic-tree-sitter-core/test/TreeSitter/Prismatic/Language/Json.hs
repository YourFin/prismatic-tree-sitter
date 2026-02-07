module TreeSitter.Prismatic.Language.Json where

import TreeSitter.Prismatic.Internal.Language.TH (stage2LanguageSplice)
import TreeSitter.Prismatic.Language.Json.Raw (json)

stage2LanguageSplice 'json json
