module TreeSitter.Prismatic.Language.Typescript where

import TreeSitter.Prismatic.Internal.Language.TH (stage2LanguageSplice)
import TreeSitter.Prismatic.Language.Typescript.Raw (typescript)

stage2LanguageSplice 'typescript typescript
