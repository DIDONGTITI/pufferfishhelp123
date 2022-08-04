module Simplex.Chat.Util where

import Data.ByteString.Char8 (ByteString)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8With)

safeDecodeUtf8 :: ByteString -> Text
safeDecodeUtf8 = decodeUtf8With onError
  where
    onError _ _ = Just '?'

uncurry3 :: (a -> b -> c -> d) -> ((a, b, c) -> d)
uncurry3 f ~(a, b, c) = f a b c

lastMaybe :: [a] -> Maybe a
lastMaybe [] = Nothing
lastMaybe xs = Just $ last xs
