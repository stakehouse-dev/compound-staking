// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {InitialsRegisterInputs, DepositInputs, StakehouseJoinInputs} from "../helpers/InputDataTypes.sol";

enum PositionStatus {
    UNUSED,
    INACTIVE,
    INITIALS_REGISTERED,
    DEPOSITED
}

/// @dev A struct encoding a pending leveraged staking position
struct Position {
    /// @dev savETHIndex owned by the wallet
    uint256 savETHIndex;

    /// @dev Current lifecycle stage of the position
    PositionStatus status;

    /// @dev The address that last initiated the strategy from INACTIVE.
    ///      The wallet is returned to this address after going through
    ///      the entire lifecycle.
    /// @notice Must be zero address when status is INACTIVE or UNUSED
    address initiator;

    /// @dev Number of KNOTs currently being processed
    /// @notice Must be 0 when status is INACTIVE or UNUSED
    uint16 nKnots;

    /// @dev Timestamp of the last update
    /// @notice Can be used to liquidate a stuck DEPOSITED position
    uint40 timestampLU;
}

interface ICompoundStakingStrategyEvents {
    /// @dev Emitted when a smart wallet is registered in the strategy
    event SmartWalletRegistered(
        address indexed registeredWallet,
        address indexed owner
    );

    /// @dev Emitted when a batch of validator initials are registered in Stakehouse for a wallet
    event ValidatorInitialsRegistered(
        address indexed wallet,
        address indexed initiator,
        uint256 nKnots
    );

    /// @dev Emitted when a batch of validator initials are deposited for
    event ValidatorsDeposited(address indexed wallet);

    /// @dev Emitted when derivatives are minted for a batch of validators and the debt is repaid
    event FinalizedAndRepaidPosition(address indexed wallet);
}

interface ICompoundStakingStrategy is ICompoundStakingStrategyEvents {}
