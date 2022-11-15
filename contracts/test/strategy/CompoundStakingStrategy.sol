// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {ITransactionRouter} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ITransactionRouter.sol";
import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {CompoundStakingBorrowingPool} from "../../CompoundStakingBorrowingPool.sol";
import {CompoundStakingStrategy} from "../../CompoundStakingStrategy.sol";
import {OwnableSmartWallet} from "../../OwnableSmartWallet.sol";
import {ICompoundStakingStrategyEvents, Position, PositionStatus} from "../../interfaces/ICompoundStakingStrategy.sol";
import {IOwnableSmartWallet} from "../../interfaces/IOwnableSmartWallet.sol";
import {CorrectnessChecks, InitialsRegisterInputs, DepositInputs, StakehouseJoinInputs} from "../../helpers/InputDataTypes.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";

import "../lib/test.sol";
import {CheatCodes, HEVM_ADDRESS} from "../lib/cheatCodes.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {InterestRateModelMock} from "../mocks/InterestRateModelMock.sol";
import {CompoundStakingTestSuite} from "../suites/TestSuite.sol";

import {RAY, LENDER, BORROWER, DUMB_ADDRESS, DUMB_ADDRESS2, DUMB_ADDRESS3, SECONDS_PER_YEAR} from "../lib/constants.sol";

contract BorrowingPoolTest is DSTest, ICompoundStakingStrategyEvents {
    CheatCodes evm = CheatCodes(HEVM_ADDRESS);

    CompoundStakingTestSuite suite;

    ERC20Mock deth;
    CompoundStakingBorrowingPool borrowingPool;
    CompoundStakingStrategy strategy;

    address interestRateModel;

    function _accessControlError(address addr, bytes32 role)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(addr),
                    " is missing role ",
                    Strings.toHexString(uint256(role), 32)
                )
            );
    }

    function _getInitialsRegisterInputs(uint256 nKnots)
        internal
        pure
        returns (InitialsRegisterInputs memory inputs)
    {
        bytes[] memory _blsPublicKey = new bytes[](nKnots);
        bytes[] memory _blsSignature = new bytes[](nKnots);

        for (uint256 i = 0; i < nKnots; ++i) {
            _blsPublicKey[i] = bytes(abi.encodePacked("Key_", i));
            _blsSignature[i] = bytes(abi.encodePacked("Sig_", i));
        }

        inputs = InitialsRegisterInputs(_blsPublicKey, _blsSignature);
    }

    function _expectInitialsRegisterCalls(
        address wallet,
        InitialsRegisterInputs memory inputs
    ) internal {
        for (uint256 i = 0; i < inputs._blsPublicKey.length; ++i) {
            evm.expectCall(
                address(suite.trMock()),
                abi.encodeWithSelector(
                    ITransactionRouter.registerValidatorInitials.selector,
                    wallet,
                    inputs._blsPublicKey[i],
                    inputs._blsSignature[i]
                )
            );
        }
    }

    function _getDepositInputs(uint256 nKnots)
        internal
        view
        returns (DepositInputs memory inputs)
    {
        bytes[] memory _blsPublicKey = new bytes[](nKnots);
        bytes[] memory _ciphertext = new bytes[](nKnots);
        bytes[] memory _aesEncryptorKey = new bytes[](nKnots);
        IDataStructures.EIP712Signature[]
            memory _encryptionSignature = new IDataStructures.EIP712Signature[](
                nKnots
            );
        bytes32[] memory _dataRoot = new bytes32[](nKnots);

        for (uint256 i = 0; i < nKnots; ++i) {
            _blsPublicKey[i] = bytes(abi.encodePacked("Key_", i));
            _ciphertext[i] = bytes(abi.encodePacked("Cipher_", i));
            _aesEncryptorKey[i] = bytes(abi.encodePacked("AES_", i));
            _encryptionSignature[i] = IDataStructures.EIP712Signature({
                deadline: uint248(block.timestamp + 100000),
                v: uint8((i + 1)),
                r: bytes32(2 * (i + 1)),
                s: bytes32(3 * (i + 1))
            });
            _dataRoot[i] = bytes32(i);
        }

        inputs = DepositInputs(
            _blsPublicKey,
            _ciphertext,
            _aesEncryptorKey,
            _encryptionSignature,
            _dataRoot
        );
    }

    function _expectDepositCalls(address wallet, DepositInputs memory inputs)
        internal
    {
        for (uint256 i = 0; i < inputs._blsPublicKey.length; ++i) {
            evm.expectCall(
                address(suite.trMock()),
                abi.encodeWithSelector(
                    ITransactionRouter.registerValidator.selector,
                    wallet,
                    inputs._blsPublicKey[i],
                    inputs._ciphertext[i],
                    inputs._aesEncryptorKey[i],
                    inputs._encryptionSignature[i],
                    inputs._dataRoot[i]
                )
            );
        }
    }

    function _getStakehouseJoinInputs(uint256 nKnots)
        internal
        view
        returns (StakehouseJoinInputs memory inputs)
    {
        bytes[] memory _blsPublicKey = new bytes[](nKnots);
        IDataStructures.ETH2DataReport[]
            memory _eth2Report = new IDataStructures.ETH2DataReport[](nKnots);
        IDataStructures.EIP712Signature[]
            memory _reportSignature = new IDataStructures.EIP712Signature[](
                nKnots
            );

        for (uint256 i = 0; i < nKnots; ++i) {
            _blsPublicKey[i] = bytes(abi.encodePacked("Key_", i));
            _eth2Report[i] = IDataStructures.ETH2DataReport({
                blsPublicKey: _blsPublicKey[i],
                withdrawalCredentials: bytes(
                    abi.encodePacked("Withdrawal_key_", i)
                ),
                slashed: false,
                activeBalance: uint64(32 gwei),
                effectiveBalance: uint64(32 gwei),
                exitEpoch: uint64(100000 * (i + 1)),
                activationEpoch: uint64(200000 * (i + 1)),
                withdrawalEpoch: uint64(300000 * (i + 1)),
                currentCheckpointEpoch: uint64(50000)
            });
            _reportSignature[i] = IDataStructures.EIP712Signature({
                deadline: uint248(block.timestamp + 100000),
                v: uint8(i + 1),
                r: bytes32(2 * (i + 1)),
                s: bytes32(3 * (i + 1))
            });
        }

        inputs = StakehouseJoinInputs(
            DUMB_ADDRESS3,
            1,
            _blsPublicKey,
            _eth2Report,
            _reportSignature
        );
    }

    function _expectStakehouseJoinCalls(
        address wallet,
        StakehouseJoinInputs memory inputs
    ) internal {
        for (uint256 i = 0; i < inputs._blsPublicKey.length; ++i) {
            evm.expectCall(
                address(suite.trMock()),
                abi.encodeWithSelector(
                    ITransactionRouter.joinStakehouse.selector,
                    wallet,
                    inputs._blsPublicKey[i],
                    inputs._stakehouse,
                    inputs._brandTokenId,
                    strategy.getPosition(wallet).savETHIndex,
                    inputs._eth2Report[i],
                    inputs._reportSignature[i]
                )
            );
        }
    }

    function _expectWithdrawDETHCalls(
        address wallet,
        StakehouseJoinInputs memory inputs
    ) internal {
        for (uint256 i = 0; i < inputs._blsPublicKey.length; ++i) {
            evm.expectCall(
                address(suite.semMock()),
                abi.encodeWithSelector(
                    ISavETHManager.addKnotToOpenIndexAndWithdraw.selector,
                    inputs._stakehouse,
                    inputs._blsPublicKey[i],
                    wallet
                )
            );
        }
    }

    function setUp() public {
        suite = new CompoundStakingTestSuite();

        deth = suite.deth();

        interestRateModel = address(
            new InterestRateModelMock(RAY / 20, RAY / 10, RAY / 2)
        );

        borrowingPool = new CompoundStakingBorrowingPool(
            address(deth),
            interestRateModel,
            "Compound Staking Pool Share",
            "shBPS"
        );

        strategy = new CompoundStakingStrategy(
            address(suite.factory()),
            address(borrowingPool),
            address(suite.trMock()),
            address(suite.semMock()),
            address(suite.amMock()),
            address(deth)
        );

        borrowingPool.grantRole(
            borrowingPool.STRATEGY_ROLE(),
            address(strategy)
        );
        strategy.grantRole(strategy.LIQUIDATOR_ROLE(), address(this));

        evm.deal(LENDER, RAY);

        evm.prank(LENDER);
        borrowingPool.deposit{value: RAY}();
    }

    /// @dev [CSS-1]: constructor sets correct values
    function test_CSS_01_constructor_sets_correct_values() public {
        assertEq(
            address(strategy.walletFactory()),
            address(suite.factory()),
            "Factory wasn't set correctly"
        );

        assertEq(
            address(strategy.borrowingPool()),
            address(borrowingPool),
            "Borrowing pool wasn't set correctly"
        );

        assertEq(
            address(strategy.transactionRouter()),
            address(suite.trMock()),
            "Transaction router wasn't set correctly"
        );

        assertEq(
            address(strategy.savETHManager()),
            address(suite.semMock()),
            "SavETH Manager wasn't set correctly"
        );

        assertEq(
            address(strategy.accountManager()),
            address(suite.amMock()),
            "Account Manager wasn't set correctly"
        );

        assertEq(
            address(strategy.deth()),
            address(deth),
            "DETH wasn't set correctly"
        );

        assertTrue(
            strategy.hasRole(strategy.CONFIGURATOR_ROLE(), address(this)),
            "Creator was not set as configurator"
        );

        assertEq(
            strategy.getRoleAdmin(strategy.LIQUIDATOR_ROLE()),
            strategy.CONFIGURATOR_ROLE(),
            "Configurator is not a strategy role admin"
        );
    }

    /// @dev [CSS-2A]: registerSmartWallet works correctly when a user passes address(0)
    function test_CSS_02A_registerSmartWallet_works_correctly_zero_address()
        public
    {
        evm.expectEmit(false, true, false, false);
        emit SmartWalletRegistered(address(0), DUMB_ADDRESS);

        evm.expectCall(
            address(suite.trMock()),
            abi.encodeWithSelector(
                ITransactionRouter.authorizeRepresentative.selector,
                address(strategy),
                true
            )
        );

        evm.prank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));

        Position memory pos = strategy.getPosition(newWallet);

        assertEq(pos.initiator, address(0), "Initiator set to non-zero value");

        assertEq(pos.savETHIndex, 1, "SavETH index id incorrect");

        assertEq(
            uint8(pos.status),
            uint8(PositionStatus.INACTIVE),
            "Position status incorrect"
        );

        assertEq(uint8(pos.nKnots), 0, "Position nKnots incorrect");

        assertEq(
            pos.timestampLU,
            block.timestamp,
            "Position timestamp incorrect"
        );

        assertTrue(
            suite.trMock().userToRepresentativeStatus(
                newWallet,
                address(strategy)
            ),
            "Wallet representative status was not set"
        );
    }

    /// @dev [CSS-2B]: registerSmartWallet works correctly when a user passes existing wallet
    function test_CSS_02B_registerSmartWallet_works_correctly_existing()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = suite.factory().createWallet();

        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);

        evm.expectEmit(false, true, false, false);
        emit SmartWalletRegistered(address(0), DUMB_ADDRESS);

        evm.expectCall(
            address(suite.trMock()),
            abi.encodeWithSelector(
                ITransactionRouter.authorizeRepresentative.selector,
                address(strategy),
                true
            )
        );

        strategy.registerSmartWallet(newWallet);

        evm.stopPrank();

        Position memory pos = strategy.getPosition(newWallet);

        assertEq(pos.initiator, address(0), "Initiator set to non-zero value");

        assertEq(pos.savETHIndex, 1, "SavETH index id incorrect");

        assertEq(
            uint8(pos.status),
            uint8(PositionStatus.INACTIVE),
            "Position status incorrect"
        );

        assertEq(uint8(pos.nKnots), 0, "Position nKnots incorrect");

        assertEq(
            pos.timestampLU,
            block.timestamp,
            "Position timestamp incorrect"
        );

        assertTrue(
            suite.trMock().userToRepresentativeStatus(
                newWallet,
                address(strategy)
            ),
            "Wallet representative status was not set"
        );
    }

    /// @dev [CSS-2C]: registerSmartWallet reverts on following cases
    ///                * wallet is being registered by non-owner
    ///                * wallet is not known to the factory
    function test_CSS_02C_registerSmartWallet_reverts_on_invalid_wallet()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = suite.factory().createWallet();

        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);

        evm.stopPrank();

        evm.expectRevert(
            "CompoundStakingStrategy: User is not the owner of provided wallet"
        );
        strategy.registerSmartWallet(newWallet);

        OwnableSmartWallet fakeWallet = new OwnableSmartWallet();

        fakeWallet.initialize(address(this));

        evm.expectRevert(
            "CompoundStakingStrategy: Wallet is not known by the factory"
        );
        strategy.registerSmartWallet(address(fakeWallet));
    }

    /// @dev [CSS-3]: registerValidatorInitialsToWallet correctly updates values and emits events
    function test_CSS_3_registerValidatorInitialsToWallet_works_correctly(
        uint256 nKnots
    ) public {
        evm.assume(nKnots > 0);
        evm.assume(nKnots < 100);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        InitialsRegisterInputs memory inputs = _getInitialsRegisterInputs(
            nKnots
        );

        evm.expectCall(
            newWallet,
            abi.encodeWithSelector(
                IOwnableSmartWallet.transferOwnership.selector,
                address(strategy)
            )
        );

        evm.expectCall(
            newWallet,
            abi.encodeWithSignature(
                "execute(address,bytes)",
                address(suite.trMock()),
                abi.encodeWithSelector(
                    ITransactionRouter.authorizeRepresentative.selector,
                    DUMB_ADDRESS,
                    true
                )
            )
        );

        _expectInitialsRegisterCalls(newWallet, inputs);

        evm.expectEmit(true, true, false, true);
        emit ValidatorInitialsRegistered(newWallet, DUMB_ADDRESS, nKnots);

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(newWallet, inputs);

        assertEq(
            strategy.getPosition(newWallet).initiator,
            DUMB_ADDRESS,
            "Position initiator was not set correctly"
        );

        assertEq(
            uint8(strategy.getPosition(newWallet).status),
            uint8(PositionStatus.INITIALS_REGISTERED),
            "Position status was not set correctly"
        );

        assertEq(
            uint8(strategy.getPosition(newWallet).nKnots),
            nKnots,
            "Position nKnots was not set correctly"
        );

        assertEq(
            strategy.getPosition(newWallet).timestampLU,
            block.timestamp,
            "Position timestamp was not set correctly"
        );
    }

    /// @dev [CSS-3A]: registerValidatorInitialsToWallet reverts on incorrect position status
    function test_CSS_3A_registerValidatorInitialsToWallet_reverts_on_incorrect_position_status()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.expectRevert(
            "CompoundStakingStrategy: Incorrect position status for this action"
        );
        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );
    }

    /// @dev [CSS-3B]: registerValidatorInitialsToWallet reverts on being called by non-owner of wallet
    function test_CSS_3B_registerValidatorInitialsToWallet_reverts_on_called_by_non_owner()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.expectRevert(
            "CompoundStakingStrategy: User is not the owner of provided wallet"
        );
        evm.prank(DUMB_ADDRESS2);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );
    }

    /// @dev [CSS-3C]: registerValidatorInitialsToWallet reverts on 0 KNOTs
    function test_CSS_3C_registerValidatorInitialsToWallet_reverts_on_called_by_non_owner()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.expectRevert("CompoundStakingStrategy: Incorrect number of KNOTs");
        evm.prank(DUMB_ADDRESS2);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(0)
        );
    }

    /// @dev [CSS-3D]: registerValidatorInitialsToWallet reverts on length mismatch
    function test_CSS_3D_registerValidatorInitialsToWallet_reverts_on_data_length_mismatch()
        public
    {
        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        InitialsRegisterInputs memory inputs = _getInitialsRegisterInputs(1);
        inputs._blsSignature = new bytes[](0);

        evm.expectRevert("InitialsRegisterInputs: Data length mismatch");
        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(newWallet, inputs);
    }

    /// @dev [CSS-4]: depositFromWalletWithLeverage correctly updates values, makes calls and emits events
    function test_CSS_4_depositFromWalletWithLeverage_works_correctly(
        uint256 nKnots
    ) public {
        evm.assume(nKnots > 0);
        evm.assume(nKnots < 100);

        uint256 fundedAmount = (nKnots * 32 ether) / 3;
        evm.deal(DUMB_ADDRESS, fundedAmount);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(nKnots)
        );

        evm.expectCall(
            newWallet,
            abi.encodeWithSignature(
                "execute(address,bytes)",
                address(suite.trMock()),
                abi.encodeWithSelector(
                    ITransactionRouter.authorizeRepresentative.selector,
                    DUMB_ADDRESS,
                    false
                )
            )
        );

        evm.expectCall(
            address(borrowingPool),
            abi.encodeWithSelector(
                CompoundStakingBorrowingPool.borrow.selector,
                newWallet,
                nKnots * 32 ether - (nKnots * 32 ether) / 3,
                address(strategy)
            )
        );

        DepositInputs memory inputs = _getDepositInputs(nKnots);

        _expectDepositCalls(newWallet, inputs);

        evm.expectEmit(true, false, false, false);
        emit ValidatorsDeposited(newWallet);

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: fundedAmount}(
            newWallet,
            inputs
        );

        assertEq(
            uint8(strategy.getPosition(newWallet).status),
            uint8(PositionStatus.DEPOSITED),
            "Position status was not set correctly"
        );

        assertEq(
            strategy.getPosition(newWallet).timestampLU,
            block.timestamp,
            "Position timestamp was not set correctly"
        );
    }

    /// @dev [CSS-4A]: depositFromWalletWithLeverage reverts on incorrect position status
    function test_CSS_4A_depositFromWalletWithLeverage_reverts_on_incorrect_position_status()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        DepositInputs memory inputs = _getDepositInputs(1);

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            inputs
        );

        evm.expectRevert(
            "CompoundStakingStrategy: Incorrect position status for this action"
        );
        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-4B]: depositFromWalletWithLeverage reverts on being called by non-initiator
    function test_CSS_4B_depositFromWalletWithLeverage_reverts_on_non_initiator()
        public
    {
        evm.deal(DUMB_ADDRESS2, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        DepositInputs memory inputs = _getDepositInputs(1);

        evm.expectRevert(
            "CompoundStakingStrategy: Only accessible by the initiator"
        );
        evm.prank(DUMB_ADDRESS2);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-4C]: depositFromWalletWithLeverage reverts on input length mismatch
    function test_CSS_4C_depositFromWalletWithLeverage_reverts_on_input_length_mismatch()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        DepositInputs memory inputs = _getDepositInputs(1);

        inputs._ciphertext = new bytes[](0);

        evm.expectRevert("DepositInputs: Data length mismatch");
        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-4D]: depositFromWalletWithLeverage reverts on leverage too high
    function test_CSS_4D_depositFromWalletWithLeverage_reverts_on_leverage_too_high()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether / 4);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        DepositInputs memory inputs = _getDepositInputs(1);

        evm.expectRevert(
            "CompoundStakingStrategy: Not enough leftover ETH to cover debt + expected interest"
        );
        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 4}(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-4E]: depositFromWalletWithLeverage reverts on data size passed != nKnots
    function test_CSS_4E_depositFromWalletWithLeverage_reverts_on_data_size_not_matching_nKnots()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether / 4);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(2)
        );

        DepositInputs memory inputs = _getDepositInputs(1);

        evm.expectRevert(
            "CompoundStakingStrategy: The dataset for mass deposit has inconsistent size with previously registered initials"
        );
        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 4}(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-5]: joinStakehouseAndRepay correctly updates values, makes calls and emits events
    function test_CSS_5_joinStakehouseAndRepay_works_correctly(uint256 nKnots)
        public
    {
        evm.assume(nKnots > 0);
        evm.assume(nKnots < 100);

        uint256 fundedAmount = (nKnots * 32 ether) / 3;
        evm.deal(DUMB_ADDRESS, fundedAmount);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(nKnots)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: fundedAmount}(
            newWallet,
            _getDepositInputs(nKnots)
        );

        evm.warp(block.timestamp + 24 * 60 * 60);

        uint256 borrowWithInterest = borrowingPool.getBorrowAmountWithInterest(
            newWallet
        );

        StakehouseJoinInputs memory inputs = _getStakehouseJoinInputs(nKnots);

        _expectStakehouseJoinCalls(newWallet, inputs);

        _expectWithdrawDETHCalls(newWallet, inputs);

        uint256 amountToRepay = nKnots * 24 ether >= borrowWithInterest
            ? borrowWithInterest
            : nKnots * 24 ether;
        uint256 loss = nKnots * 24 ether >= borrowWithInterest
            ? 0
            : borrowWithInterest - nKnots * 24 ether;

        evm.expectCall(
            address(borrowingPool),
            abi.encodeWithSelector(
                CompoundStakingBorrowingPool.repay.selector,
                newWallet,
                amountToRepay,
                loss
            )
        );

        evm.expectCall(
            newWallet,
            abi.encodeWithSelector(
                IOwnableSmartWallet.transferOwnership.selector,
                DUMB_ADDRESS
            )
        );

        evm.expectEmit(true, false, false, false);
        emit FinalizedAndRepaidPosition(newWallet);

        evm.prank(DUMB_ADDRESS);
        strategy.joinStakehouseAndRepay(newWallet, inputs);

        assertEq(
            strategy.getPosition(newWallet).initiator,
            address(0),
            "Initiator was not erased"
        );

        assertEq(
            strategy.getPosition(newWallet).timestampLU,
            block.timestamp,
            "Timestamp was not updated"
        );

        assertEq(
            uint8(strategy.getPosition(newWallet).status),
            uint8(PositionStatus.INACTIVE),
            "Status was not updated"
        );

        assertEq(
            strategy.getPosition(newWallet).nKnots,
            0,
            "nKnots was not erased"
        );
    }

    /// @dev [CSS-5A]: joinStakehouseAndRepay reverts on incorrect position status
    function test_CSS_5A_joinStakehouseAndRepay_reverts_on_incorrect_position_status()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        evm.warp(block.timestamp + 24 * 60 * 60);

        evm.prank(DUMB_ADDRESS);
        strategy.joinStakehouseAndRepay(
            newWallet,
            _getStakehouseJoinInputs(1)
        );

        evm.expectRevert(
            "CompoundStakingStrategy: Incorrect position status for this action"
        );
        evm.prank(DUMB_ADDRESS);
        strategy.joinStakehouseAndRepay(
            newWallet,
            _getStakehouseJoinInputs(1)
        );
    }

    /// @dev [CSS-5B]: joinStakehouseAndRepay reverts on non initiator
    function test_CSS_5B_joinStakehouseAndRepay_reverts_on_non_initiator()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        evm.expectRevert(
            "CompoundStakingStrategy: Only accessible by the initiator"
        );
        evm.prank(DUMB_ADDRESS2);
        strategy.joinStakehouseAndRepay(
            newWallet,
            _getStakehouseJoinInputs(1)
        );
    }

    /// @dev [CSS-5C]: joinStakehouseAndRepay reverts on data length mismatch
    function test_CSS_5C_joinStakehouseAndRepay_reverts_on_data_length_mismatch()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        StakehouseJoinInputs memory inputs = _getStakehouseJoinInputs(1);

        inputs._blsPublicKey = new bytes[](0);

        evm.expectRevert("StakehouseJoinInputs: Data length mismatch");
        evm.prank(DUMB_ADDRESS);
        strategy.joinStakehouseAndRepay(
            newWallet,
            inputs
        );
    }

    /// @dev [CSS-5D]: joinStakehouseAndRepay reverts on data not matching recorded nKnots
    function test_CSS_5D_joinStakehouseAndRepay_reverts_on_data_size_not_matching_nKnots()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        evm.expectRevert("CompoundStakingStrategy: The dataset for mass deposit has inconsistent size with previously registered initials");
        evm.prank(DUMB_ADDRESS);
        strategy.joinStakehouseAndRepay(
            newWallet,
            _getStakehouseJoinInputs(2)
        );
    }

    /// @dev [CSS-6]: liquidateStuckPosition correctly updates values, makes calls and emits events
    function test_CSS_6_liquidateStuckPosition_works_correctly(uint256 nKnots)
        public
    {
        evm.assume(nKnots > 0);
        evm.assume(nKnots < 100);

        uint256 fundedAmount = (nKnots * 32 ether) / 3;
        evm.deal(DUMB_ADDRESS, fundedAmount);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(nKnots)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: fundedAmount}(
            newWallet,
            _getDepositInputs(nKnots)
        );

        evm.warp(block.timestamp + 31 * 24 * 60 * 60);

        uint256 borrowWithInterest = borrowingPool.getBorrowAmountWithInterest(
            newWallet
        );

        StakehouseJoinInputs memory inputs = _getStakehouseJoinInputs(nKnots);

        _expectStakehouseJoinCalls(newWallet, inputs);

        _expectWithdrawDETHCalls(newWallet, inputs);

        uint256 amountToRepay = nKnots * 24 ether >= borrowWithInterest
            ? borrowWithInterest
            : nKnots * 24 ether;
        uint256 loss = nKnots * 24 ether >= borrowWithInterest
            ? 0
            : borrowWithInterest - nKnots * 24 ether;

        evm.expectCall(
            address(borrowingPool),
            abi.encodeWithSelector(
                CompoundStakingBorrowingPool.repay.selector,
                newWallet,
                amountToRepay,
                loss
            )
        );

        evm.expectCall(
            newWallet,
            abi.encodeWithSelector(
                IOwnableSmartWallet.transferOwnership.selector,
                DUMB_ADDRESS2
            )
        );

        evm.expectEmit(true, false, false, false);
        emit FinalizedAndRepaidPosition(newWallet);

        strategy.liquidateStuckPosition(newWallet, DUMB_ADDRESS2, inputs);

        assertEq(
            strategy.getPosition(newWallet).initiator,
            address(0),
            "Initiator was not erased"
        );

        assertEq(
            strategy.getPosition(newWallet).timestampLU,
            block.timestamp,
            "Timestamp was not updated"
        );

        assertEq(
            uint8(strategy.getPosition(newWallet).status),
            uint8(PositionStatus.INACTIVE),
            "Status was not updated"
        );

        assertEq(
            strategy.getPosition(newWallet).nKnots,
            0,
            "nKnots was not erased"
        );
    }

    /// @dev [CSS-6A]: liquidateStuckPosition reverts when position is not yet qualified as stuck
    function test_CSS_6A_liquidateStuckPosition_reverts_on_position_not_yet_stuck()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        evm.warp(block.timestamp + 24 * 60 * 60);

        evm.expectRevert(
            "CompoundStakingStrategy: Liquidating a position that is not yet stuck"
        );
        strategy.liquidateStuckPosition(
            newWallet,
            DUMB_ADDRESS2,
            _getStakehouseJoinInputs(1)
        );
    }

    /// @dev [CSS-6B]: liquidateStuckPosition reverts on being called by non-liquidator
    function test_CSS_6B_liquidateStuckPosition_reverts_on_non_liquidator()
        public
    {
        evm.deal(DUMB_ADDRESS, 32 ether);

        evm.startPrank(DUMB_ADDRESS);
        address newWallet = strategy.registerSmartWallet(address(0));
        IOwnableSmartWallet(newWallet).setApproval(address(strategy), true);
        evm.stopPrank();

        evm.prank(DUMB_ADDRESS);
        strategy.registerValidatorInitialsToWallet(
            newWallet,
            _getInitialsRegisterInputs(1)
        );

        evm.prank(DUMB_ADDRESS);
        strategy.depositFromWalletWithLeverage{value: 32 ether / 2}(
            newWallet,
            _getDepositInputs(1)
        );

        evm.warp(block.timestamp + 24 * 60 * 60);

        evm.expectRevert(
            bytes(_accessControlError(DUMB_ADDRESS, strategy.LIQUIDATOR_ROLE()))
        );
        evm.prank(DUMB_ADDRESS);
        strategy.liquidateStuckPosition(
            newWallet,
            DUMB_ADDRESS2,
            _getStakehouseJoinInputs(1)
        );
    }

    /// @dev [CSS-7]: strategy reverts when it receives ETH from non-pool address
    function test_CSS_7_strategy_reverts_on_receiving_ETH_from_non_pool()
        public
    {
        evm.deal(address(this), 1 ether);
        evm.expectRevert("CompoundStakingStrategy: ETH received directly from an address that is not the pool");
        payable(address(strategy)).transfer(1 ether);
    }
}
