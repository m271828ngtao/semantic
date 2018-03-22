module Data.Abstract.Module
( Module(..)
, ModuleName
, moduleForBlob
) where

import Data.Abstract.FreeVariables
import Data.Blob
import qualified Data.ByteString.Char8 as BC
import Data.Language
import Data.List.Split (splitWhen)
import System.FilePath.Posix

type ModuleName = Name

data Module term = Module { moduleName :: ModuleName, modulePath :: FilePath, moduleBody :: term }
  deriving (Eq, Foldable, Functor, Ord, Show, Traversable)


-- | Construct a 'Module' for a 'Blob' and @term@, relative to some root 'FilePath'.
moduleForBlob :: Maybe FilePath -- ^ The root directory relative to which the module will be resolved, if any.
              -> Blob           -- ^ The 'Blob' containing the module.
              -> term           -- ^ The @term@ representing the body of the module.
              -> Module term    -- ^ A 'Module' named appropriate for the 'Blob', holding the @term@, and constructed relative to the root 'FilePath', if any.
moduleForBlob rootDir blob term = Module (moduleName blob) (blobPath blob) term
  where moduleName Blob{..} | Just Go <- blobLanguage = toName (takeDirectory (modulePath blobPath))
                            | otherwise               = toName                (modulePath blobPath)
                            -- TODO: Need a better way to handle module registration and resolution
        toName = qualifiedName . map BC.pack . splitWhen (== pathSeparator)
        modulePath = dropExtensions . maybe takeFileName makeRelative rootDir
