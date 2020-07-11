{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Simplex.Messaging.Client where

import Control.Monad.Trans.Except
import Control.Protocol (PartyCmd (..))
import Polysemy.Internal
import Simplex.Messaging.Protocol

instance Monad m => PartyProtocol m Recipient where
  api ::
    SimplexCommand from (Cmd Recipient s s') a ->
    Connection Recipient s ->
    ExceptT String m (a, Connection Recipient s')
  api (PushConfirm _ _) = apiStub
  api (PushMsg _ _) = apiStub

  action ::
    SimplexCommand (Cmd Recipient s s') to a ->
    Connection Recipient s ->
    ExceptT String m a ->
    ExceptT String m (Connection Recipient s')
  action (CreateConn _) = actionStub
  action (Subscribe _) = actionStub
  action (Unsubscribe _) = actionStub
  action (SendInvite _) = actionStub
  action (SecureConn _ _) = actionStub
  action (DeleteMsg _ _) = actionStub

instance Monad m => PartyProtocol m Sender where
  api ::
    SimplexCommand from (Cmd Sender s s') a ->
    Connection Sender s ->
    ExceptT String m (a, Connection Sender s')
  api (SendInvite _) = apiStub

  action ::
    SimplexCommand (Cmd Sender s s') to a ->
    Connection Sender s ->
    ExceptT String m a ->
    ExceptT String m (Connection Sender s')
  action (ConfirmConn _ _) = actionStub
  action (SendMsg _ _) = actionStub

type SimplexRecipient = SimplexParty Recipient

type SimplexSender = SimplexParty Sender

rApi ::
  Member SimplexRecipient r =>
  SimplexCommand from (Cmd Recipient s s') a ->
  Connection Recipient s ->
  Sem r (Either String (a, Connection Recipient s'))
rApi cmd conn = send $ Api cmd conn

rAction ::
  Member SimplexRecipient r =>
  SimplexCommand (Cmd Recipient s s') to a ->
  Connection Recipient s ->
  Either String a ->
  Sem r (Either String (Connection Recipient s'))
rAction cmd conn res = send $ Action cmd conn res

sApi ::
  Member SimplexSender r =>
  SimplexCommand from (Cmd Sender s s') a ->
  Connection Sender s ->
  Sem r (Either String (a, Connection Sender s'))
sApi cmd conn = send $ Api cmd conn

sAction ::
  Member SimplexSender r =>
  SimplexCommand (Cmd Sender s s') to a ->
  Connection Sender s ->
  Either String a ->
  Sem r (Either String (Connection Sender s'))
sAction cmd conn res = send $ Action cmd conn res
