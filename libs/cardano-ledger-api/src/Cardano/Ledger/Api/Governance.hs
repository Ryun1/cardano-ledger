{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Cardano.Ledger.Api.Governance (
  EraGovernance (GovernanceState),
  emptyGovernanceState,
  getProposedPPUpdates,

  -- * Shelley
  ShelleyPPUPState (..),
  ProposedPPUpdates (..),
  emptyPPPUpdates,

  -- * Conway

  -- ** Conway Governance
  ConwayGovernance (..),
  cgRatifyL,
  cgTallyL,
  ConwayTallyState (..),
  RatifyState (..),
  EnactState (..),
  Voter (..),
  Vote (..),

  -- ** Governance Action
  GovernanceAction (..),
  GovernanceActionId (..),
  GovernanceActionIx (..),
  GovernanceActionState (..),

  -- *** Anchor
  Anchor (..),
  AnchorData (..),
  AnchorDataHash,
  hashAnchorData,
) where

import Cardano.Ledger.Api.Era ()
import Cardano.Ledger.Conway.Governance (
  Anchor (..),
  AnchorDataHash,
  ConwayGovernance (..),
  ConwayTallyState (..),
  EnactState (..),
  GovernanceAction (..),
  GovernanceActionId (..),
  GovernanceActionIx (..),
  GovernanceActionState (..),
  RatifyState (..),
  Vote (..),
  Voter (..),
  -- Lenses

  cgRatifyL,
  cgTallyL,
 )
import Cardano.Ledger.Crypto (Crypto)
import Cardano.Ledger.SafeHash (HashAnnotated, SafeHash, SafeToHash, hashAnnotated)
import Cardano.Ledger.Shelley.Governance (
  EraGovernance (GovernanceState),
  ShelleyPPUPState (..),
  emptyGovernanceState,
  getProposedPPUpdates,
 )
import Cardano.Ledger.Shelley.PParams (ProposedPPUpdates (..), emptyPPPUpdates)
import Data.ByteString (ByteString)

newtype AnchorData c = AnchorData ByteString
  deriving (Eq, SafeToHash)

instance HashAnnotated (AnchorData c) AnchorDataHash c

-- | Hash `AnchorData`
hashAnchorData :: Crypto c => AnchorData c -> SafeHash c AnchorDataHash
hashAnchorData = hashAnnotated
