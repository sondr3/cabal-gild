module CabalGild.Type.LegacyExeDependency where

import qualified CabalGild.Type.VersionRange as VersionRange
import qualified Data.Function as Function
import qualified Distribution.Parsec as Parsec
import qualified Distribution.Pretty as Pretty
import qualified Distribution.Types.LegacyExeDependency as LegacyExeDependency

-- | This type exists to provide an 'Ord' instance for
-- 'LegacyExeDependency.LegacyExeDependency', which was added in
-- @Cabal-syntax-3.10.1.0@.
newtype LegacyExeDependency = LegacyExeDependency
  { unwrap :: LegacyExeDependency.LegacyExeDependency
  }
  deriving (Eq, Show)

instance Ord LegacyExeDependency where
  compare =
    Function.on compare $
      (\(LegacyExeDependency.LegacyExeDependency s vr) -> (s, VersionRange.fromVersionRange vr))
        . unwrap

instance Parsec.Parsec LegacyExeDependency where
  parsec = LegacyExeDependency <$> Parsec.parsec

instance Pretty.Pretty LegacyExeDependency where
  pretty = Pretty.pretty . unwrap
