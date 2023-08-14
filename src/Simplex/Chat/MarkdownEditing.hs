{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use newtype instead of data" #-}
{-# LANGUAGE InstanceSigs #-}


module Simplex.Chat.MarkdownEditing 
    ( DiffedChar(..)
    , DiffStatus(..)
    , DiffUnchangedTextuallyStatus(..)
    , FormattedChar(..)
    , findDiffs
    )
    where

import           Data.Aeson (ToJSON)
import qualified Data.Aeson as J
import qualified Data.Foldable as F
import qualified Data.Map.Strict as M
import           Data.Sequence ( Seq(..), (><) )
import qualified Data.Sequence as S
import           Data.Text (Text)
import qualified Data.Text as T
import           GHC.Generics ( Generic )
import           Simplex.Messaging.Parsers ( sumTypeJSON ) 
import qualified Data.Diff.Myers as D
import           Simplex.Chat.Markdown ( FormattedText(..), Format )
import qualified Debug.Trace as DBG


data DiffStatus 
    = UnchangedTextually DiffUnchangedTextuallyStatus
    | Inserted 
    | Deleted 
    -- todo Replaced  -- same as Delete+Insert    
    deriving (Show, Eq)

data DiffUnchangedTextuallyStatus
    = Pristine
    | ChangedToFormat {newFormat :: Maybe Format}
    deriving (Show, Eq)

data DiffedChar = DiffedChar FormattedChar DiffStatus
    deriving (Show, Eq)

data FormattedChar = FormattedChar 
    { char :: Char
    , format :: Maybe Format
    }
    deriving (Show, Eq)

-- todo What is this for?
data EditedText =  EditedText 
    { format :: Maybe Format
    , text :: Text
    , added :: Maybe Bool
    }
    deriving (Eq, Show, Generic)

instance ToJSON EditedText where
    toEncoding :: EditedText -> J.Encoding
    toEncoding = J.genericToEncoding $ sumTypeJSON id


newtype DeleteIndicies = DeleteIndicies (Seq Int) deriving (Show, Eq)
newtype InsertIndicies = InsertIndicies (Seq Int) deriving (Show, Eq)


-- toEditedChars :: [FormattedText] -> [EditedChar]
-- toEditedChars = concatMap toChars
--   where
--     toChars FormattedText {format, text} =
--       map (\char -> EditedChar {format, char, operation = Nothing}) $ T.unpack text


toFormattedChars :: [FormattedText] -> [FormattedChar]
toFormattedChars = concatMap toChars
    where toChars (FormattedText f t) = map (`FormattedChar` f) $ T.unpack t


-- fromEditedChars :: [EditedChar] -> [EditedText]
-- fromEditedChars = reverse . foldl' addChar []
--   where
--     addChar :: [EditedText] -> EditedChar -> [EditedText]
--     addChar [] c = [toText c]
--     addChar ts@(t : rest) c
--       | sameFormat t c = appendChar t c : rest
--       | otherwise = toText c : ts

--     toText :: EditedChar -> EditedText
--     toText EditedChar {format, char, added} = EditedText {format, text = T.singleton char, added}
    
--     sameFormat :: EditedText -> EditedChar -> Bool
--     sameFormat EditedText {format, added} EditedChar {format = format', added = added'} = format == format' && added == added'
    
--     appendChar :: EditedText -> EditedChar -> EditedText
--     appendChar t@EditedText {text} EditedChar {char} = t {text = text <> T.singleton char}


findDiffs :: Seq FormattedChar -> Seq FormattedChar -> Seq DiffedChar
findDiffs left right = 
    let
        toText :: Seq FormattedChar -> T.Text
        toText = T.pack . F.toList . fmap char  

        edits :: Seq D.Edit
        edits = DBG.trace ("edits: " <> show (D.diffTexts (toText left) (toText right) )) $ D.diffTexts (toText left) (toText right)  

        indices :: (DeleteIndicies, InsertIndicies)
        indices = F.foldl' f (DeleteIndicies S.empty, InsertIndicies S.empty) edits
            where
            f :: (DeleteIndicies, InsertIndicies) -> D.Edit -> (DeleteIndicies, InsertIndicies)
            f (x@(DeleteIndicies ds), y@(InsertIndicies is)) e = case e of
                D.EditDelete   m n -> (x', y)  where x' = DeleteIndicies $ ds >< S.fromList [m .. n]  
                D.EditInsert _ m n -> (x , y') where y' = InsertIndicies $ is >< S.fromList [m .. n] 

        (DeleteIndicies deleteIndicies, InsertIndicies insertIndicies) = DBG.trace ("indices: " <> show indices) indices
            
        unchangedTextually :: Seq (Int, FormattedChar, FormattedChar) -- indexed in original
        unchangedTextually = DBG.trace ("unchangedTextually: " <> show (f <$> S.zip leftWithoutDeletes rightWithoutInserts)) $ f <$> S.zip leftWithoutDeletes rightWithoutInserts
            where
            leftWithoutDeletes :: Seq (Int, FormattedChar) 
            leftWithoutDeletes = DBG.trace ("leftWithoutDeletes: " <> show (S.filter (\(i, _) -> i `notElem` deleteIndicies) leftZ)) $ S.filter (\(i, _) -> i `notElem` deleteIndicies) leftZ -- indexed in original
                where leftZ = S.zip (S.fromList [0 .. S.length left]) left

            rightWithoutInserts :: Seq (Int, FormattedChar)
            rightWithoutInserts = DBG.trace ("rightWithoutInserts: " <> show (S.filter (\(i, _) -> i `notElem` insertIndicies) rightZ)) $ S.filter (\(i, _) -> i `notElem` insertIndicies) rightZ -- indexed in original
                where rightZ = S.zip (S.fromList [0 .. S.length right]) right

            f :: ((Int, FormattedChar), (Int, FormattedChar)) -> (Int, FormattedChar, FormattedChar)
            f ((i,c), (_,d)) = (i,c,d)
       
        unchangedTextualies :: M.Map Int DiffUnchangedTextuallyStatus
        unchangedTextualies = DBG.trace ("unchangedTextualies: " <> show (F.foldl' f M.empty unchangedTextually)) $ F.foldl' f M.empty unchangedTextually
            where
            f :: M.Map Int DiffUnchangedTextuallyStatus -> (Int, FormattedChar, FormattedChar) -> M.Map Int DiffUnchangedTextuallyStatus
            f acc (i, FormattedChar _ fL, FormattedChar _ fR) = M.insert i x acc
                where x = if fL == fR then Pristine else ChangedToFormat {newFormat = fR}

        markDeletesAndUnchangedTextually :: Seq DiffedChar
        markDeletesAndUnchangedTextually = DBG.trace ("markDeletesAndUnchangedTextually: " <> show (S.mapWithIndex f left)) $ S.mapWithIndex f left
            where
                f :: Int -> FormattedChar -> DiffedChar
                f i x = DiffedChar x $
                    if i `elem` deleteIndicies then Deleted 
                    else UnchangedTextually $ unchangedTextualies M.! i -- should never error

        addInserts :: Seq DiffedChar -> Seq DiffedChar
        addInserts base = DBG.trace ("addInserts: " <> show (F.foldr f base edits)) $ F.foldr f base edits -- start from end and work backwards, hence foldr
            where
            f :: D.Edit -> Seq DiffedChar -> Seq DiffedChar
            f e acc = case e of
                D.EditDelete {} -> acc
                D.EditInsert i m n -> S.take i acc >< inserts >< S.drop i acc
                    where 
                    rightFormatChars = S.take (n - m + 1) $ S.drop m right
                    inserts = fmap (`DiffedChar` Inserted) rightFormatChars

        result = DBG.trace ("result: " <> show (addInserts markDeletesAndUnchangedTextually)) $ addInserts markDeletesAndUnchangedTextually
  in
        result