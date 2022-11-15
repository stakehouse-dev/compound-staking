// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOwnableSmartWalletFactory} from "./interfaces/IOwnableSmartWalletFactory.sol";
import {IOwnableSmartWallet} from "./interfaces/IOwnableSmartWallet.sol";
import {IBorrowingPool} from "./interfaces/IBorrowingPool.sol";
import {ICompoundStakingStrategy, PositionStatus, Position} from "./interfaces/ICompoundStakingStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import {ITransactionRouter} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ITransactionRouter.sol";
import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {IAccountManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IAccountManager.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {EXPECTED_ETH2_DEPOSIT_DURATION, DEPOSIT_AMOUNT, DETH_MINTED_AMOUNT, TIME_UNTIL_STUCK} from "./helpers/Constants.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {CorrectnessChecks, InitialsRegisterInputs, DepositInputs, StakehouseJoinInputs} from "./helpers/InputDataTypes.sol";

/// @title Compound staking strategy
/// @notice Allows depositors to open Stakehouse KNOTs with leverage, i.e.,
///         borrowing ETH to deposit for KNOTs that they can't
///         fund themselves, and then repaying from derivatives
///         minted by stakehouse.
contract CompoundStakingStrategy is
    ReentrancyGuard,
    AccessControl,
    ICompoundStakingStrategy
{
    /// @dev Identifier for the Configurator (owner) role
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @dev Identifier for the Liquidator role
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @dev The factory for smart wallets holding KNOTs
    IOwnableSmartWalletFactory public immutable walletFactory;

    /// @dev Pool providing ETH liquidity for leveraged deposits
    IBorrowingPool public immutable borrowingPool;

    /// @dev Stakehouse protocol Transaction router
    ITransactionRouter public immutable transactionRouter;

    /// @dev Stakehouse protocol SavETHManager
    ISavETHManager public immutable savETHManager;

    /// @dev Stakehouse protocol Account Manager
    IAccountManager public immutable accountManager;

    /// @dev Address of DETH
    address public immutable deth;

    /// @dev Mapping from smart wallet addresses to their corresponding positions
    mapping(address => Position) internal pendingPositions;

    /// @dev Contract constructor
    /// @param _factory Address of the Smart Wallet Factory
    /// @param _borrowingPool Address of the ETH borrowing pool
    /// @param _transactionRouter Address of Stakehouse TransactionRouter
    /// @param _savETHManager Address of Stakehouse SavETHManager
    /// @param _accountManager Address of Stakehouse AccountManager
    /// @param _deth Address of the DETH token
    constructor(
        address _factory,
        address _borrowingPool,
        address _transactionRouter,
        address _savETHManager,
        address _accountManager,
        address _deth
    ) {
        walletFactory = IOwnableSmartWalletFactory(_factory); // F: [CSS-1]
        borrowingPool = IBorrowingPool(_borrowingPool); // F: [CSS-1]
        transactionRouter = ITransactionRouter(_transactionRouter); // F: [CSS-1]
        savETHManager = ISavETHManager(_savETHManager); // F: [CSS-1]
        accountManager = IAccountManager(_accountManager); // F: [CSS-1]
        deth = _deth; // F: [CSS-1]

        _grantRole(CONFIGURATOR_ROLE, msg.sender); // F: [CSS-1]
        _setRoleAdmin(LIQUIDATOR_ROLE, CONFIGURATOR_ROLE); // F: [CSS-1]
    }

    /// @dev Restricts function on a wallet to a particular lifecycle stage
    ///      If in the middle of executing the strategy, additionally checks
    ///      that the msg.sender is the address that originally started executing
    ///      the strategy for this wallet.
    /// @param wallet Address of a smart wallet
    /// @param status Lifecycle status to restrict the function to
    modifier checkWalletStatus(address wallet, PositionStatus status) {
        require(
            pendingPositions[wallet].status == status,
            "CompoundStakingStrategy: Incorrect position status for this action"
        );

        _;
    }

    /// @dev Restricts function on a wallet to only being called by
    ///      position initiator
    /// @param wallet Address of a smart wallet
    modifier onlyInitiator(address wallet) {
        require(
            pendingPositions[wallet].initiator == msg.sender,
            "CompoundStakingStrategy: Only accessible by the initiator"
        );
        _;
    }

    /// @dev Transfers the configurator role to another address
    /// @notice Restricted to configurator only.
    /// @notice Caution! The action is irreversible and can lead to loss
    ///         of control if the new address is wrong.
    function setConfigurator(address newConfigurator)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        _grantRole(CONFIGURATOR_ROLE, newConfigurator);
        _revokeRole(CONFIGURATOR_ROLE, msg.sender);
    }

    /// @dev Returns a position associated with a wallet
    /// @param wallet The wallet to return position for
    function getPosition(address wallet)
        external
        view
        returns (Position memory)
    {
        return pendingPositions[wallet];
    }

    /// @dev Prepares a wallet to be used with the strategy and
    ///      initializes the associated position
    /// @param wallet Wallet address, if it already exists. Otherwise,
    ///               passing address(0) would create a new wallet
    /// @notice Can only be called once for a particular wallet. The user can set
    ///         `userToRepresentativeStatus` and the SavETH index owner to different
    ///         values, after which the wallet may no longer be usable with this contract.
    function registerSmartWallet(address wallet)
        public
        nonReentrant
        checkWalletStatus(wallet, PositionStatus.UNUSED)
        returns (address registeredWallet)
    {
        if (wallet == address(0)) {
            // If the wallet doesn't exist, creates a new one
            registeredWallet = walletFactory.createWallet(address(this)); // F: [CSS-2A]
        } else {
            // Otherwise, performs sanity checks and transfers the wallet
            // to itself to prepare the wallet
            require(
                IOwnableSmartWallet(wallet).owner() == msg.sender,
                "CompoundStakingStrategy: User is not the owner of provided wallet"
            ); // F: [CSS-2C]
            require(
                walletFactory.walletExists(wallet),
                "CompoundStakingStrategy: Wallet is not known by the factory"
            ); // F: [CSS-2C]
            IOwnableSmartWallet(wallet).transferOwnership(address(this)); // F: [CSS-2B]
            registeredWallet = wallet; // F: [CSS-2B]
        }

        // The strategy must be the wallet's representative, in order to
        // create KNOTs on its behalf

        if (
            !transactionRouter.userToRepresentativeStatus(
                registeredWallet,
                address(this)
            )
        ) {
            IOwnableSmartWallet(registeredWallet).execute(
                address(transactionRouter),
                abi.encodeWithSelector(
                    ITransactionRouter.authorizeRepresentative.selector,
                    address(this),
                    true
                )
            ); // F: [CSS-2A, 2B]
        }

        // Creates a savETH index to be used as a buffer for wallet's
        // dETH after minting the derivatives

        uint256 savETHIndex = savETHManager.createIndex(registeredWallet); // F: [CSS-2A, 2B]

        pendingPositions[registeredWallet] = Position({
            savETHIndex: savETHIndex,
            nKnots: 0,
            initiator: address(0),
            status: PositionStatus.INACTIVE,
            timestampLU: uint40(block.timestamp)
        }); // F: [CSS-2A, 2B]

        IOwnableSmartWallet(registeredWallet).transferOwnership(msg.sender); // F: [CSS-2A, 2B]

        emit SmartWalletRegistered(registeredWallet, msg.sender); // F: [CSS-2A, 2B]
    }

    /// @dev Registers a batch of validator initials with the Stakehouse protocol,
    ///      with the wallet as depositor
    /// @param wallet Wallet to register initials for
    /// @param inputs A struct containing Stakehouse-specific inputs for initials registration
    ///        * _blsPublicKey - Array of validator BLS public keys
    ///        * _blsSignature - Array of signatures under provided validator keys
    function registerValidatorInitialsToWallet(
        address wallet,
        InitialsRegisterInputs calldata inputs
    )
        public
        nonReentrant
        checkWalletStatus(wallet, PositionStatus.INACTIVE) // F: [CSS-3A]
    {
        // Checks that at least 1 KNOT is being created
        require(
            inputs._blsPublicKey.length > 0 &&
                inputs._blsPublicKey.length < 65536,
            "CompoundStakingStrategy: Incorrect number of KNOTs"
        ); // F: [CSS-3C]

        // Checks that input data is correct, e.g.,
        // that all arrays are of the same length
        CorrectnessChecks.checkCorrectness(inputs); // F: [CSS-3D]

        // Transfers the wallet to the strategy and records
        // msg.sender as original strategy initiator
        _initiateStrategyForWallet(wallet); // F: [CSS-3]

        uint16 nKnots = uint16(inputs._blsPublicKey.length); // F: [CSS-3]

        // Registers initials with Stakehouse
        // for all BLS keys
        _massRegisterInitials(wallet, inputs, nKnots); // F: [CSS-3]

        Position memory position = pendingPositions[wallet];

        position.initiator = msg.sender;
        position.status = PositionStatus.INITIALS_REGISTERED;
        position.nKnots = nKnots;
        position.timestampLU = uint40(block.timestamp);

        pendingPositions[wallet] = position; // F: [CSS-3]

        emit ValidatorInitialsRegistered(wallet, msg.sender, nKnots); // F: [CSS-3]
    }

    /// @dev Registers initials in Stakehouse for a batch of BLS keys
    /// @param wallet Wallet to register initials for
    /// @param inputs A struct containing Stakehouse-specific inputs for initials registration
    ///        * _blsPublicKey - Array of validator BLS public keys
    ///        * _blsSignature - Array of signatures under provided validator keys
    /// @param nKnots Number of KNOTs to register initials for
    function _massRegisterInitials(
        address wallet,
        InitialsRegisterInputs memory inputs,
        uint256 nKnots
    ) internal {
        for (uint256 i = 0; i < nKnots; ) {
            transactionRouter.registerValidatorInitials(
                wallet,
                inputs._blsPublicKey[i],
                inputs._blsSignature[i]
            ); // F: [CSS-3]

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Makes a deposit for a batch of BLS keys registered to a smart wallet
    ///      through Stakehouse, borrowing additional funds from the pool, if required
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _blsPublicKey - An array of BLS keys to deposit for
    ///        * _ciphertext - Array of signing key ciphertexts for disaster recovery
    ///        * _aesEncryptorKey - Ciphertexts of AES keys used for BLS signing key encryption
    ///        * _encryptionSignature - Encryption validity signatures, issued by disaster recovery committee
    ///        * _dataRoot - Roots of DepositMessage SSZ containers
    function depositFromWalletWithLeverage(
        address wallet,
        DepositInputs calldata inputs
    )
        external
        payable
        nonReentrant
        checkWalletStatus(wallet, PositionStatus.INITIALS_REGISTERED) // F: [CSS-4A]
        onlyInitiator(wallet) // F: [CSS-4B]
    {
        _removeInitiatorRepresentative(wallet);

        // Checks that input data is correct, e.g.,
        // that all arrays are of the same length
        CorrectnessChecks.checkCorrectness(inputs); // F: [CSS-4C]

        Position memory position = pendingPositions[wallet];

        // Checks that length of passed data if the same as the previously
        // registered initials set. While the initiator can pass a different
        // set of BLS keys of the same size, there is no particular benefit
        // for them to do so
        require(
            position.nKnots == inputs._blsPublicKey.length,
            "CompoundStakingStrategy: The dataset for mass deposit has inconsistent size with previously registered initials"
        ); // F: [CSS-4E]

        // Borrows additional funds if required,
        // and makes deposits for all BLS keys through stakehouse
        _depositWithLeverage(wallet, position.nKnots, inputs); // F: [CSS-4]

        position.status = PositionStatus.DEPOSITED; // F: [CSS-4]
        position.timestampLU = uint40(block.timestamp); // F: [CSS-4]

        pendingPositions[wallet] = position; // F: [CSS-4]

        emit ValidatorsDeposited(wallet); // F: [CSS-4]
    }

    /// @dev Makes a deposit for several KNOTs, partially with borrowed funds
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param nKnots Number of KNOTs to register
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _blsPublicKey - An array of BLS keys to deposit for
    ///        * _ciphertext - Array of signing key ciphertexts for disaster recovery
    ///        * _aesEncryptorKey - Ciphertexts of AES keys used for BLS signing key encryption
    ///        * _encryptionSignature - Encryption validity signatures, issued by disaster recovery committee
    ///        * _dataRoot - Roots of DepositMessage SSZ containers
    function _depositWithLeverage(
        address wallet,
        uint256 nKnots,
        DepositInputs memory inputs
    ) internal {
        // Computes the amount required to deposit for all KNOTs
        // and borrows the shortfall from the pool
        _fundExtraKnots(nKnots, msg.value, wallet); // F: [CSS-4]

        // Deposits for all BLS keys through stakehouse
        _massRegisterValidators(wallet, nKnots, inputs); // F: [CSS-4]
    }

    /// @dev Checks whether the funded value is enough to cover all deposits,
    ///      if not, borrows the shortfall from the pool
    /// @param nKnots Number of KNOTs to deposit for
    /// @param fundedValue The amount of ETH provided by the initiator themselves
    /// @param wallet Address of the depositor smart wallet, which will also be a borrower
    function _fundExtraKnots(
        uint256 nKnots,
        uint256 fundedValue,
        address wallet
    ) internal {
        // The function handles the case when there is enough money to cover all deposits
        // A user may want to use the contract even without leverage, i.e., to batch deposit KNOTs
        // with a Smart Wallet, to make them transferrable
        if (fundedValue < nKnots * DEPOSIT_AMOUNT) {
            uint256 borrowedAmount = nKnots * DEPOSIT_AMOUNT - fundedValue;

            // The function checks that the minted amount covers the entire principal +
            // at least 3 days worth of interest. Typically, deposits should not
            // take more than 24 hours, so 72 hours should provide a sufficient buffer
            require(
                nKnots * DETH_MINTED_AMOUNT >=
                    borrowedAmount +
                        borrowingPool.getExpectedInterest(
                            borrowedAmount,
                            EXPECTED_ETH2_DEPOSIT_DURATION
                        ),
                "CompoundStakingStrategy: Not enough leftover ETH to cover debt + expected interest"
            ); // F: [CSS-4D]


            borrowingPool.borrow(wallet, borrowedAmount, address(this)); // F: [CSS-4]
        }
    }

    /// @dev Registers a batch of validators through Stakehouse
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param nKnots Number of KNOTs to register
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _blsPublicKey - An array of BLS keys to deposit for
    ///        * _ciphertext - Array of signing key ciphertexts for disaster recovery
    ///        * _aesEncryptorKey - Ciphertexts of AES keys used for BLS signing key encryption
    ///        * _encryptionSignature - Encryption validity signatures, issued by disaster recovery committee
    ///        * _dataRoot - Roots of DepositMessage SSZ containers
    function _massRegisterValidators(
        address wallet,
        uint256 nKnots,
        DepositInputs memory inputs
    ) internal {
        for (uint256 i = 0; i < nKnots; ) {
            transactionRouter.registerValidator{value: DEPOSIT_AMOUNT}(
                wallet,
                inputs._blsPublicKey[i],
                inputs._ciphertext[i],
                inputs._aesEncryptorKey[i],
                inputs._encryptionSignature[i],
                inputs._dataRoot[i]
            ); // F: [CSS-4]

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Mints Stakehouse derivatives for a batch of BLS keys that successfully
    ///      deposited to Consensus chain, then repays debt to the borrowing pool
    ///      from minted dETH.
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _stakehouse - Stakehouse address to join
    ///        * _brandTokenId - ID of a Stakehouse brand to join
    ///        * _blsPublicKey - An array of BLS keys to mint derivatives for
    ///        * _eth2Report - ETH2 data reports proving successful deposit for each BLS key
    ///        * _reportSignature - Committee signatures validating veracity of ETH2 reports
    function joinStakehouseAndRepay(
        address wallet,
        StakehouseJoinInputs calldata inputs
    )
        external
        nonReentrant
        checkWalletStatus(wallet, PositionStatus.DEPOSITED) // F: [CSS-5A]
        onlyInitiator(wallet) // F: [CSS-5B]
    {
        // Checks that input data is correct, e.g.,
        // that all arrays are of the same length
        CorrectnessChecks.checkCorrectness(inputs); // F: [CSS-5C]

        Position memory position = pendingPositions[wallet];

        require(
            position.nKnots == inputs._blsPublicKey.length,
            "CompoundStakingStrategy: The dataset for mass deposit has inconsistent size with previously registered initials"
        ); // F: [CSS-5D]

        // Mints derivatives for all BLS keys
        _massJoinStakehouse(
            wallet,
            position.nKnots,
            position.savETHIndex,
            inputs
        ); // F: [CSS-5]

        // Withdraws all DETH from the index to repay the debt to the borrowing pool
        _massWithdrawDETH(wallet, position.nKnots, inputs); // F: [CSS-5]

        // Repays debt from minted DETH
        _repayDebtToPool(wallet); // F: [CSS-5]

        IOwnableSmartWallet(wallet).transferOwnership(position.initiator); // F: [CSS-5]

        emit FinalizedAndRepaidPosition(wallet); // F: [CSS-5]

        position.initiator = address(0); // F: [CSS-5]
        position.timestampLU = uint40(block.timestamp); // F: [CSS-5]
        position.status = PositionStatus.INACTIVE; // F: [CSS-5]
        position.nKnots = 0; // F: [CSS-5]

        pendingPositions[wallet] = position; // F: [CSS-5]
    }

    /// @dev Used to rescue stuck positions that already deposited for a batch of BLS keys.
    ///      Similar to joinStakehouseAndRepay but transfers the smart wallet to the designated recipient rather
    ///      than position initiator.
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param recipient The recipient of the smart wallet from stuck position
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _stakehouse - Stakehouse address to join
    ///        * _brandTokenId - ID of a Stakehouse brand to join
    ///        * _blsPublicKey - An array of BLS keys to mint derivatives for
    ///        * _eth2Report - ETH2 data reports proving successful deposit for each BLS key
    ///        * _reportSignature - Committee signatures validating veracity of ETH2 reports
    /// @notice Only accessible to designated liquidator address
    function liquidateStuckPosition(
        address wallet,
        address recipient,
        StakehouseJoinInputs calldata inputs
    )
        external
        checkWalletStatus(wallet, PositionStatus.DEPOSITED)
        onlyRole(LIQUIDATOR_ROLE) // F: [CSS-6B]
    {
        // Checks that input data is correct, e.g.,
        // that all arrays are of the same length
        CorrectnessChecks.checkCorrectness(inputs);

        Position memory position = pendingPositions[wallet];

        require(
            block.timestamp - position.timestampLU > TIME_UNTIL_STUCK,
            "CompoundStakingStrategy: Liquidating a position that is not yet stuck"
        ); // F: [CSS-6A]

        require(
            position.nKnots == inputs._blsPublicKey.length,
            "CompoundStakingStrategy: The dataset for mass deposit has inconsistent size with previously registered initials"
        );

        // Mints derivatives for all BLS keys
        _massJoinStakehouse(
            wallet,
            position.nKnots,
            position.savETHIndex,
            inputs
        ); // F: [CSS-6]

        // Withdraws all DETH from the index to repay the debt to the borrowing pool
        _massWithdrawDETH(wallet, position.nKnots, inputs); // F: [CSS-6]

        // Repays debt from minted DETH
        _repayDebtToPool(wallet); // F: [CSS-6]

        IOwnableSmartWallet(wallet).transferOwnership(recipient); // F: [CSS-6]

        emit FinalizedAndRepaidPosition(wallet); // F: [CSS-6]

        position.initiator = address(0); // F: [CSS-6]
        position.timestampLU = uint40(block.timestamp); // F: [CSS-6]
        position.nKnots = 0; // F: [CSS-6]
        position.status = PositionStatus.INACTIVE; // F: [CSS-6]

        pendingPositions[wallet] = position; // F: [CSS-6]
    }

    /// @dev Repays the wallet's debt to the pool. If the wallet
    ///      does not have sufficient funds, pays the entire balance
    ///      and records a loss
    /// @param wallet Wallet to repay debt for
    function _repayDebtToPool(address wallet) internal {
        uint256 amountToRepay = borrowingPool.getBorrowAmountWithInterest(
            wallet
        );
        uint256 availableDETH = IERC20(deth).balanceOf(wallet);
        uint256 loss;

        if (amountToRepay > availableDETH) {
            // If there is not enough DETH to repay, repays what it can
            // This should be very rare, as the strategy checks that there is
            // a large surplus to cover possibly delayed deposits
            loss = amountToRepay - availableDETH;
            amountToRepay = availableDETH;
        } // F: [CSS-5, 6]

        // The wallet approves DETH to the pool, since the pool
        // will transfer the debt from it
        IOwnableSmartWallet(wallet).execute(
            address(deth),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(borrowingPool),
                amountToRepay
            )
        ); // F: [CSS-5, 6]

        borrowingPool.repay(wallet, amountToRepay, loss); // F: [CSS-5, 6]
    }

    /// @dev Mints stakehouse derivatives for a batch of BLS keys
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param nKnots Number of KNOTs to mint derivatives for
    /// @param _savETHIndexId ID of a SavETH index to isolate KNOTs into
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _stakehouse - Stakehouse address to join
    ///        * _brandTokenId - ID of a Stakehouse brand to join
    ///        * _blsPublicKey - An array of BLS keys to mint derivatives for
    ///        * _eth2Report - ETH2 data reports proving successful deposit for each BLS key
    ///        * _reportSignature - Committee signatures validating veracity of ETH2 reports
    function _massJoinStakehouse(
        address wallet,
        uint256 nKnots,
        uint256 _savETHIndexId,
        StakehouseJoinInputs memory inputs
    ) internal {
        for (uint256 i; i < nKnots; ) {
            transactionRouter.joinStakehouse(
                wallet,
                inputs._blsPublicKey[i],
                inputs._stakehouse,
                inputs._brandTokenId,
                _savETHIndexId,
                inputs._eth2Report[i],
                inputs._reportSignature[i]
            ); // F: [CSS-5, 6]

            unchecked {
                ++i;
            }
        }
    }

    /// @dev For a batch of BLS keys, returns all KNOTs into the Open Index
    ///      and withdraws all DETH
    /// @param wallet The wallet acting as a depositor for provided BLS keys
    /// @param nKnots Number of KNOTs to de-isolate and withdraw DETH from
    /// @param inputs Struct encoding Stakehouse-specific data
    ///        * _stakehouse - Stakehouse address to join
    ///        * _brandTokenId - ID of a Stakehouse brand to join
    ///        * _blsPublicKey - An array of BLS keys to mint derivatives for
    ///        * _eth2Report - ETH2 data reports proving successful deposit for each BLS key
    ///        * _reportSignature - Committee signatures validating veracity of ETH2 reports
    function _massWithdrawDETH(
        address wallet,
        uint256 nKnots,
        StakehouseJoinInputs memory inputs
    ) internal {
        for (uint256 i; i < nKnots; ) {
            IOwnableSmartWallet(wallet).execute(
                address(savETHManager),
                abi.encodeWithSelector(
                    ISavETHManager.addKnotToOpenIndexAndWithdraw.selector,
                    inputs._stakehouse,
                    inputs._blsPublicKey[i],
                    wallet
                )
            ); // F: [CSS-5, 6]

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Transfers ownership of wallet to the strategy
    ///      and records the previous owner as initiator
    /// @param wallet The wallet to initiate the strategy for
    function _initiateStrategyForWallet(address wallet) internal {
        require(
            IOwnableSmartWallet(wallet).owner() == msg.sender,
            "CompoundStakingStrategy: User is not the owner of provided wallet"
        ); // F: [CSS-3B]
        IOwnableSmartWallet(wallet).transferOwnership(address(this)); // F: [CSS-3]

        IOwnableSmartWallet(wallet).execute(
            address(transactionRouter),
            abi.encodeWithSelector(
                ITransactionRouter.authorizeRepresentative.selector,
                msg.sender,
                true
            )
        ); 

        pendingPositions[wallet].initiator = msg.sender; // F: [CSS-3]
    }

    /// @dev Removes the representative status of the initiator
    ///      Representative status is required after registering initials
    ///      but needs to be removed after depositing, to avoid issues with the lifecycle
    ///      of the position
    /// @param wallet The wallet to initiate the strategy for
    function _removeInitiatorRepresentative(address wallet) internal {
        IOwnableSmartWallet(wallet).execute(
            address(transactionRouter),
            abi.encodeWithSelector(
                ITransactionRouter.authorizeRepresentative.selector,
                msg.sender,
                false
            )
        ); 
    }

    /// @notice Only the borrowing pool should be able to send ETH directly to this contract
    receive() external payable {
        require(
            msg.sender == address(borrowingPool),
            "CompoundStakingStrategy: ETH received directly from an address that is not the pool"
        ); // F: [CSS-7]
    }
}
