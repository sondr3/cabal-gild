{-# LANGUAGE TypeApplications #-}

module CabalGild.Action.FormatFields where

import qualified CabalGild.Extra.FieldLine as FieldLine
import qualified CabalGild.Extra.Name as Name
import qualified CabalGild.Extra.String as String
import qualified CabalGild.Type.Dependency as Dependency
import qualified CabalGild.Type.ExeDependency as ExeDependency
import qualified CabalGild.Type.ForeignLibOption as ForeignLibOption
import qualified CabalGild.Type.Language as Language
import qualified CabalGild.Type.LegacyExeDependency as LegacyExeDependency
import qualified CabalGild.Type.ModuleReexport as ModuleReexport
import qualified CabalGild.Type.PkgconfigDependency as PkgconfigDependency
import qualified CabalGild.Type.SomeParsecParser as SPP
import qualified CabalGild.Type.TestedWith as TestedWith
import qualified Data.Functor.Identity as Identity
import qualified Data.Map as Map
import qualified Distribution.CabalSpecVersion as CabalSpecVersion
import qualified Distribution.FieldGrammar.Newtypes as Newtypes
import qualified Distribution.Fields as Fields
import qualified Distribution.ModuleName as ModuleName
import qualified Distribution.Parsec as Parsec
import qualified Distribution.Types.Mixin as Mixin
import qualified Language.Haskell.Extension as Extension
import qualified Text.PrettyPrint as PrettyPrint

-- | A wrapper around 'field' to allow this to be composed with other actions.
run ::
  (Applicative m, Monoid cs) =>
  CabalSpecVersion.CabalSpecVersion ->
  ([Fields.Field cs], cs) ->
  m ([Fields.Field cs], cs)
run csv (fs, cs) = pure (fmap (field csv) fs, cs)

-- | Formats the given field, if applicable. Otherwise returns the field as is.
-- If the field is a section, the fields within the section will be recursively
-- formatted.
field ::
  (Monoid cs) =>
  CabalSpecVersion.CabalSpecVersion ->
  Fields.Field cs ->
  Fields.Field cs
field csv f = case f of
  Fields.Field n fls -> case Map.lookup (Name.value n) parsers of
    Nothing -> f
    Just spp -> Fields.Field n $ fieldLines csv fls spp
  Fields.Section n sas fs -> Fields.Section n sas $ fmap (field csv) fs

-- | Attempts to parse the given field lines using the given parser. If parsing
-- fails, the field lines will be returned as is. Comments within the field
-- lines will be preserved but "float" up to the top.
fieldLines ::
  (Monoid cs) =>
  CabalSpecVersion.CabalSpecVersion ->
  [Fields.FieldLine cs] ->
  SPP.SomeParsecParser ->
  [Fields.FieldLine cs]
fieldLines csv fls SPP.SomeParsecParser {SPP.parsec = parsec, SPP.pretty = pretty} =
  case Parsec.runParsecParser' csv parsec "" $ FieldLine.toFieldLineStream fls of
    Left _ -> fls
    Right r ->
      fmap (\(c, l) -> Fields.FieldLine c $ String.toUtf8 l)
        . zip (foldMap FieldLine.annotation fls : repeat mempty)
        . lines
        . PrettyPrint.renderStyle style
        $ pretty csv r

-- | This style attempts to force everything to be on its own line.
style :: PrettyPrint.Style
style =
  PrettyPrint.Style
    { PrettyPrint.mode = PrettyPrint.PageMode,
      PrettyPrint.lineLength = 0,
      PrettyPrint.ribbonsPerLine = 1
    }

-- | A map from field names to parsers. This determines which parser should be
-- used for which field. And consequently this determines which fields will be
-- formatted.
--
-- Perhaps instead of being keyed on 'Fields.FieldName', this should be keyed
-- on a path (list of field names) instead. That's because a field like
-- @build-depends@ only really makes sense within a section like @library@.
-- Fortunately field names are unique enough that this hasn't been a problem
-- yet.
parsers :: Map.Map Fields.FieldName SPP.SomeParsecParser
parsers =
  let (=:) :: String -> SPP.SomeParsecParser -> (Fields.FieldName, SPP.SomeParsecParser)
      (=:) = (,) . String.toUtf8
   in Map.fromList
        [ "asm-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "asm-sources" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "autogen-includes" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "autogen-modules" =: SPP.set @Newtypes.VCat @(Newtypes.MQuoted ModuleName.ModuleName),
          "build-depends" =: SPP.set @Newtypes.CommaVCat @(Identity.Identity Dependency.Dependency),
          "build-tool-depends" =: SPP.set @Newtypes.CommaFSep @(Identity.Identity ExeDependency.ExeDependency),
          "build-tools" =: SPP.set @Newtypes.CommaFSep @(Identity.Identity LegacyExeDependency.LegacyExeDependency),
          "c-sources" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "cc-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "cmm-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "cmm-sources" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "code-generators" =: SPP.list @Newtypes.CommaFSep @Newtypes.Token,
          "cpp-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "cxx-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "cxx-sources" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "data-files" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "default-extensions" =: SPP.set @Newtypes.FSep @(Newtypes.MQuoted Extension.Extension),
          "exposed-modules" =: SPP.set @Newtypes.VCat @(Newtypes.MQuoted ModuleName.ModuleName),
          "extensions" =: SPP.set @Newtypes.FSep @(Newtypes.MQuoted Extension.Extension),
          "extra-bundled-libraries" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-doc-files" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "extra-dynamic-library-flavours" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-framework-dirs" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "extra-ghci-libraries" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-lib-dirs-static" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "extra-lib-dirs" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "extra-libraries-static" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-libraries" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-library-flavours" =: SPP.set @Newtypes.VCat @Newtypes.Token,
          "extra-source-files" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "extra-tmp-files" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "frameworks" =: SPP.set @Newtypes.FSep @Newtypes.Token,
          "ghc-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "ghc-prof-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "ghc-shared-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "ghcjs-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "ghcjs-prof-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "ghcjs-shared-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "hs-source-dirs" =: SPP.list @Newtypes.FSep @Newtypes.FilePathNT,
          "hsc2hs-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "include-dirs" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "includes" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "install-includes" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "js-sources" =: SPP.set @Newtypes.VCat @Newtypes.FilePathNT,
          "ld-options" =: SPP.list @Newtypes.NoCommaFSep @Newtypes.Token',
          "license-files" =: SPP.set @Newtypes.FSep @Newtypes.FilePathNT,
          "mixins" =: SPP.set @Newtypes.CommaVCat @(Identity.Identity Mixin.Mixin),
          "options" =: SPP.set @Newtypes.FSep @(Identity.Identity ForeignLibOption.ForeignLibOption),
          "other-extensions" =: SPP.set @Newtypes.FSep @(Newtypes.MQuoted Extension.Extension),
          "other-languages" =: SPP.set @Newtypes.FSep @(Newtypes.MQuoted Language.Language),
          "other-modules" =: SPP.set @Newtypes.VCat @(Newtypes.MQuoted ModuleName.ModuleName),
          "pkgconfig-depends" =: SPP.set @Newtypes.CommaFSep @(Identity.Identity PkgconfigDependency.PkgconfigDependency),
          "reexported-modules" =: SPP.set @Newtypes.CommaVCat @(Identity.Identity ModuleReexport.ModuleReexport),
          "setup-depends" =: SPP.set @Newtypes.CommaVCat @(Identity.Identity Dependency.Dependency),
          "signatures" =: SPP.set @Newtypes.VCat @(Newtypes.MQuoted ModuleName.ModuleName),
          "tested-with" =: SPP.set @Newtypes.FSep @(Identity.Identity TestedWith.TestedWith),
          "virtual-modules" =: SPP.set @Newtypes.VCat @(Newtypes.MQuoted ModuleName.ModuleName)
        ]
