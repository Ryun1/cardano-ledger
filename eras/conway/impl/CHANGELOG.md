# Version history for `cardano-ledger-conway`

## 1.8.0.0

* Change `ToJSONKey` implementation of `Voter` to flat text
* Add DRep refund calculation #3688
  * Add `conwayConsumedValue` as `getConsumedValue` for Conway
* Change `PredicateFailure (ConwayENACT era)` to `Void`
* Remove `EnactPredFailure`
* Change `PredicateFailure (ConwayEPOCH era)` to `Void`
* Remove `ConwayEpochPredFailure`
* Remove `EpochFailure` and `RatifyFailure` from `ConwayNewEpochPredFailure`
* Change `PredicateFailure (ConwayRATIFY era)` to `Void`
* Add:
  * `rsDelayed`
  * `PParamGroup`
  * `ParamGrouper`
  * `pGroup`
  * `pUngrouped`
  * `modifiedGroups`
  * `dvtPPNetworkGroupL`
  * `dvtPPGovGroupL`
  * `dvtPPTechnicalGroupL`
  * `dvtPPEconomicGroupL`
  * `threshold`
  * `ensCommitteeL`
* Add `pparamsGroups` to `ConwayEraPParams`
* Add `PrevGovActionIds`
* Change `EnactState` to add `ensPrevGovActionIds`
* Add  `ensPrevGovActionIdsL`, `ensPrevPParamUpdateL`, `ensPrevHardForkL` `ensPrevCommitteeL`, `ensPrevConstitutionL`
* Add `EnactSignal` and the signal of `Enact` to it
* Remove `rsFuture` from `RatifyState`
* Add to `GovActionsState`:
  * `curGovActionsState`
  * `prevGovActionsState`
  * `prevDRepState`
  * `prevCommitteeState`
* Add `ToExpr` instances to:
  * `PoolVotingThresholds`
  * `DRepVotingThresholds`
  * `GovActionState`
  * `GovActionsState`
  * `EnactState`
  * `RatifyState`
  * `ConwayGovState`
  * `GovActionIx`
  * `GovActionId`
  * `Vote`
  * `Committee`
  * `PrevGovActionId`
  * `GovAction`
  * `ConwayPParams` with `Identity` and `StrictMaybe`
* Add lenses:
  * `cgEnactStateL`
  * `curGovActionsStateL`
  * `prevGovActionsStateL`
  * `prevDRepStateL`
  * `prevCommitteeStateL`
* Replace `cgRatifyState` with `cgEnactState`
* Deprecate `cgRatifyStateL`
* Add `ProposalDepositIncorrect` predicate failure, that is produced when `ProposalProcedure` deposit does not match `"govActionDeposit"` from `PParams` #3669
* Add "minCommitteeSize" `PParam` validation for `NewCommittee` `GovAction` #3668
  * Add `committeeMembersL` and `committeeQuorumL` lenses for `Committee`
  * Add `NewCommitteeSizeTooSmall` `PredicateFailure` in `GOV`
* Add `EqRaw` instance for `ConwayTxBody`
* Add `ToExpr` instance for `Delegatee`, `ConwayDelegCert`, `ConwayGovCert` and
  `ConwayTxCert`
* Implement expiry for governance proposals #3664
  * Update `ppGovActionExpiration` to be an `EpochNo`
  * Add `gasExpiresAfter :: !EpochNo` to `GovActionState`
  * Add `gePParams` to `GovEnv`
  * Rename `teTxId` to `geTxId` and `teEpoch` to `geEpoch`
* Add `reDRepState` to `RatifyEnv`
* Add field `gasId` to `GovActionState`
* Add `insertGovActionsState`
* Change type of `rsRemoved` in `RatifyState` to use  `GovActionState` instead of a tuple
* Change `RatifySignal` to use `GovActionsState` instead of a tuple
* Add `FromJSON` instance for `Committee`
* Add `constitution` and `committee` fields to `ConwayGenesis`

## 1.7.1.0

* Fix DRep distribution computation.

## 1.7.0.0

* Add `Network` validation for `ProposalProcedure` and `TreasuryWithdrawals` in GOV #3659
* Make `DELEG`, `POOL` and `GOVCERT` conform to spec-v0.8 #3628
  * Add `CertEnv` and `CertsEnv` to pass `EpochNo` down from `LEDGER` to sub-rules
  * Add `drepDeposit` to `DRepState` to track deposits paid by `DRep`s
  * Update `DRep` expiry in `LEDGER` for all `DRep`s who are voting in current `Tx`
* Add `ConwayGovCertEnv`
* Change the environment of `GOVCERT` to `ConwayGovCertEnv`
* Add `ConwayEraGov` with `constitutionGovStateL`
* Add `PrevGovActionId` and `GovActionPurpose`
* Add optional `PrevGovActionId` to `ParameterChange`, `HardForkInitiation`,
  `NoConfidence`, `NewCommittee` and `NewConstitution` governance actions.
* Rename `*governance*` to `*gov*` #3607
  * `GovernanceAction` to `GovAction`
  * `GovernanceActionId` to `GovActionId`
  * `GovernanceActionIx` to `GovActionIx`
  * `GovernanceActionState` to `GovActionState`
  * `ConwayGovState` to `GovActionsState`
  * `ConwayGovernance` to `ConwayGovState`
* Add `MalformedProposal` to `ConwayGovPredFailure`
* Add `ppuWellFormed` to `ConwayEraPParams`
* Filter out zero valued `TxOut`'s on Byron/Shelley boundary instead of on Babbage/Conway.
* Deprecate `translateTxOut` in favor of `upgradeTxOut`
* Deprecate `translateScript` in favor of `upgradeScript`
* Switch GovernanceActionIx to `Word32` fro `Word64` and remove `Num` and `Enum`
  instances, which are dangerous due to potential overflows.
* Add `currentTreasuryValue :: !(StrictMaybe Coin)` as a new field to Conway TxBody #3586
* Add an optional Anchor to the Conway DRep registration certificate #3576
* Change `ConwayCommitteeCert` to allow:
  * committee cold keys to be script-hashes #3581
  * committee hot keys to be script-hashes #3552
* Change EnactState.ensConstitution #3556
  * from `SafeHash (EraCrypto era) ByteString`
  * to `Constitution era`
  * Use this datatype for GovernanceAction.NewConstitution
* Add `ConwayPParams` #3498
  * Add `UpgradeConwayPParams`
  * Add `ConwayEraPParams`
  * Add `PoolVotingThresholds`
  * Add `DRepVotingThresholds`
* Rename:
   * `cgTally` -> `cgGovActionsState`
   * `cgTallyL` -> `cgGovActionsStateL`
   * `VDelFailure` -> `GovCertFailure`
   * `VDelEvent` -> `GovCertEvent`
   * `certVState` -> `certGState`
   * `ConwayVDelPredFailure` -> `ConwayGovCertPredFailure`
   * `ConwayTallyPredFailure` -> `ConwayGovPredFailure`
   * `TallyEnv` -> `GovEnv`
   * `ConwayTallyState` -> `ConwayGovState`
   * `TALLY` -> `GOV`
   * `VDEL` -> `GOVCERT`
* Make `Anchor` required in `ProposalProcedure`.
* Add `ConwayUTXO`
* Add `indexedGovProps`
* Add `rsRemoved` to `RatifyState`
* Add `conwayProducedValue`
* Changed the superclasses of `STS (ConwayUTXOS era)`
* Add `VotingProcedures` type
* Remove `vProcGovActionId` and `vProcVoter` from `VotingProcedure`
* Change the type of `votingProceduresL` to return `VotingProcedures`, which is a nested Map
  instead of a sequence, as before.
* Change `GovernanceActionDoesNotExist` to `GovernanceActionsDoNotExist`, which now
  reports all actions as a set, rather than one action per each individual failure.
* Type of `gpVotingProcedures` in `GovernanceProcedures` was aslo changed to `GovernanceProcedures`
* Rename:
  * `ConwayCommitteeCert` -> `ConwayGovCert`
  * `ConwayTxCertCommittee` -> `ConwayTxCertGov`
* Remove `DelegStakeTxCert` from the `COMPLETE` pragma for `TxCert`
* Add `Committee` and adjust `NewCommittee` governance action
* Add `treasuryDonationTxBodyL` to `ConwayEraTxBody`
* Add `ConwayUpdateDRep` constructor to `ConwayGovCert` type and corresponding pattern `UnRegDRepTxCert`
* Update `ProposalProcedure` return address to be a `RewardAcnt`
* Add `ensPrevPParams` field to `EnactState`
* Add lenses:
  * `ensPrevPParamsL`
  * `ensCurPParamsL`

## 1.6.3.0

* Implement stake distribution handling in the `TICKF` rule.

## 1.6.2.0

* Add implementation for `spendableInputsTxBodyL`

## 1.6.1.0

* Removal of TxOuts with zero `Coin` from UTxO on translation

## 1.6.0.0

* Removal of `GovernanceProcedure` in favor of `GovernanceProcedures`

## 1.5.0.0

* Add `ensConstitutionL` and `rsEnactStateL` to `Governance` #3506
  * Override `getConsitutionHash` for Conway to return just the hash of the constitution
* Added `ConwayWdrlNotDelegatedToDRep` to `ConwayLedgerPredFailure`
* Changed the type of voting delegatee from `Credential` to `DRep`
* Removal of `VoterRole` in favor of `Voter`
* Removal of `vProcRole` and `vProcRoleKeyHash` in favor of `vProcVoter` in `VotingProcedure`
* Removal of `cgVoterRolesL` and `cgVoterRoles` for `ConwayGovernance` as no longer needed.
* Removal of `gasVotes` in favor of `gasCommitteeVotes`, `gasDRepVotes` and
  `gasStakePoolVotes` in `GovernanceActionState`
* Removal of `reRoles` from `RatifyEnv` as no longer needed
* Addition of `reStakePoolDistr` to `RatifyEnv`
* Remove `VoterDoesNotHaveRole` as no longer needed from `ConwayTallyPredFailure`
* Added `ConwayEpochPredFailure`
* Added instance for `Embed (ConwayRATIFY era) (ConwayEPOCH era)`
* Removed instance for `Embed (ConwayRATIFY era) (ConwayNEWEPOCH era)`
* Changed superclasses of `STS (ConwayEPOCH era)` and `STS (ConwayNEWEPOCH era)`

## 1.4.0.0

* Added `ConwayUTXOW` rule

### `testlib`

* Add `Arbitrary` instances for `ConwayCertPredFailure`, `ConwayVDelPredFailure`, and `ConwayDelegPredFailure`

## 1.3.0.0

* Add `VDEL` rules to Conway #3467
* Add `EncCBOR`/`DecCBOR` for `ConwayCertPredFailure`
* Add `EncCBOR`/`DecCBOR` for `ConwayVDelPredFailure`
* Add `POOL` rules to Conway #3464
  * Make `ShelleyPOOL` rules reusable in Conway
* Add `CERT` and `DELEG` rules to Conway #3412
  * Add `domDeleteAll` to `UMap`.
* Introduction of `TxCert` and `EraTxCert`
* Add `ConwayEraTxCert`
* Add `EraTxCert`, `ShelleyEraTxCert` and `ConwayEraTxCert` instances for `ConwayEra`
* Add `EraPlutusContext 'PlutusV1` instance to `ConwayEra`
* Add `EraPlutusContext 'PlutusV2` instance to `ConwayEra`
* Add `EraPlutusContext 'PlutusV3` instance to `ConwayEra`
* Added `toShelleyDelegCert` and `fromShelleyDelegCert`
* Changed `ConwayDelegCert` structure #3408
* Addition of `getScriptWitnessConwayTxCert` and `getVKeyWitnessConwayTxCert`
* Add `ConwayCommitteeCert`

## 1.2.0.0

* Added `ConwayDelegCert` and `Delegatee` #3372
* Removed `toShelleyDCert` and `fromShelleyDCertMaybe` #3372
* Replace `DPState c` with `CertState era`
* Add `TranslateEra` instances for:
  * `DState`
  * `PState`
  * `VState`
* Add `ConwayDelegsPredFailure`
* Renamed `DELPL` to `CERT`
* Added `ConwayDELEGS` rule
* Added `ConwayCERT` rule
* Added `ConwayDelegsPredFailure` rule
* Added `ConwayDelegsEvent` rule
* Change the Conway txInfo to allow Plutus V3
  NOTE - unlike V1 and V2, the ledger will no longer place the "zero ada" value
  in the script context for the transaction minting field.
* Added instances for ConwayDelegsPredFailure:
  `NoThunks`, `EncCBOR`, `DecCBOR`, and `Arbitrary`
* Added `GovernanceActionMetadata`
* Added `RatifyEnv` and `RatifySignal`

## 1.1.0.0

* Added `RATIFY` rule
* Added `ConwayGovernance`
* Added lenses:
  * `cgTallyL`
  * `cgRatifyL`
  * `cgVoterRolesL`
* Removed `GovernanceActionInfo`
* Replaced `ctbrVotes` and `ctbrGovActions` with `ctbrGovProcedure`
* Renamed `ENACTMENT` to `ENACT`
* Add `ToJSON` instance for: #3323
  * `ConwayGovernance`
  * `ConwayTallyState`
  * `GovernanceAction`
  * `GovernanceActionState`
  * `GovernanceActionIx`
  * `GovernanceActionId`
* Add `ToJSONKey` instance for `GovernanceActionId` #3323
* Fix `EncCBOR`/`DecCBOR` and `ToCBOR`/`FromCBOR` for `ConwayTallyState` #3323
* Add `Anchor` and `AnchorDataHash` types. #3323
* Rename `transDCert` to `toShelleyDCert`
* Add `fromShelleyDCertMaybe`
* Renamed `Vote` type to `VotingProcedure`
* Add `ProposalProcedure`
* Use `VotingProcedure` and `ProposalProcedure` in `GovernanceProcedure`
* Rename `VoteDecision` to `Vote`. Rename `No`/`Yes` -> `VoteNo`/`VoteYes`.
* Export `govActionIdToText`
* Export constructors for `ConwayTallyPredFailure`
* Add `ensTreasury` and `ensWithdrawals` to `EnactState` #3339
* Add `EnactPredFailure` as the failure for `ENACT` and `RATIFY` #3339
* Add `RatifyFailure` to `ConwayNewEpochPredFailure` #3339
* Add `EncCBOR`/`DecCBOR` and `ToCBOR`/`FromCBOR` for `ConwayTallyPredFailure`
* Add `ToCBOR`/`FromCBOR` for `ConwayGovernance`
* Remove `cgAlonzoGenesis` from `ConwayGenesis`.
* Set `ConwayGenesis` as `TranslationContext`

### `testlib`

* Fix `Arbitrary` for `ConwayTallyState`. #3323
* Consolidate all `Arbitrary` instances from the test package to under a new `testlib`. #3285
* Add `Arbitrary` instances for:
  * `ConwayTallyPredFailure`
  * `EnactState`
  * `RatifyState`
  * `ConwayGovernance`
* Fix `Arbitrary` for `ConwayTxBody`.

## 1.0.0.0

* First properly versioned release.
