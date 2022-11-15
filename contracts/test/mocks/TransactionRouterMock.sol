// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ITransactionRouter} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ITransactionRouter.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import {IAccountManagerMock} from "./AccountManagerMock.sol";
import {ISavETHManagerMock} from "./SavETHManagerMock.sol";
import {DEPOSIT_AMOUNT} from "../../helpers/Constants.sol";

contract TransactionRouterMock is ITransactionRouter {
    IAccountManagerMock accountManagerMock;
    ISavETHManagerMock savETHManagerMock;

    mapping(address => mapping(address => bool))
        public userToRepresentativeStatus;

    mapping(bytes => bool) public blsKeyDeposited;

    constructor(address _accountManagerMock, address _savETHManagerMock) {
        accountManagerMock = IAccountManagerMock(_accountManagerMock);
        savETHManagerMock = ISavETHManagerMock(_savETHManagerMock);
    }

    function authorizeRepresentative(address _representative, bool _enabled)
        external
    {
        userToRepresentativeStatus[msg.sender][_representative] = _enabled;
    }

    function registerValidatorInitials(
        address _user,
        bytes calldata _blsPublicKey,
        bytes calldata _blsSignature
    ) external {
        require(
            userToRepresentativeStatus[_user][msg.sender],
            "TransactionRouterMock: Representative not authorized"
        );

        accountManagerMock.recordAccountData(
            _user,
            _blsPublicKey,
            _blsSignature
        );
    }

    function registerValidator(
        address _user,
        bytes calldata _blsPublicKey,
        bytes calldata _ciphertext,
        bytes calldata _aesEncryptorKey,
        IDataStructures.EIP712Signature calldata _encryptionSignature,
        bytes32 _dataRoot
    ) external payable {
        require(
            userToRepresentativeStatus[_user][msg.sender],
            "TransactionRouterMock: Representative not authorized"
        );

        require(
            msg.value == DEPOSIT_AMOUNT,
            "TransactionRouterMock: Deposit amount incorrect"
        );

        require(
            accountManagerMock.areInitialsRegistered(_blsPublicKey),
            "TransactionRouterMock: Validator initials not registered"
        );
        require(
            accountManagerMock.getAccountByPublicKey(_blsPublicKey).depositor ==
                _user,
            "TransactionRouterMock: User is not the depositor"
        );

        accountManagerMock.recordDepositStatus(_blsPublicKey);
    }

    function joinStakehouse(
        address _user,
        bytes calldata _blsPublicKey,
        address _stakehouse,
        uint256,
        uint256,
        IDataStructures.ETH2DataReport calldata,
        IDataStructures.EIP712Signature calldata
    ) external {
        require(
            userToRepresentativeStatus[_user][msg.sender],
            "TransactionRouterMock: Representative not authorized"
        );
        require(
            accountManagerMock.getAccountByPublicKey(_blsPublicKey).depositor ==
                _user,
            "TransactionRouterMock: User is not the depositor"
        );
        require(
            accountManagerMock.depositIsProcessed(_blsPublicKey),
            "TransactionRouterMock: Deposit not yet processed"
        );

        savETHManagerMock.prepareDETHForKNOT(_stakehouse, _blsPublicKey);
    }

    function createStakehouse(
        address _user,
        bytes calldata _blsPublicKey,
        string calldata _ticker,
        uint256 _savETHIndexId,
        IDataStructures.ETH2DataReport calldata _eth2Report,
        IDataStructures.EIP712Signature calldata _reportSignature
    ) external pure {
        revert("TransactionRouterMock: Not implemented");
    }

    function joinStakeHouseAndCreateBrand(
        address _user,
        bytes calldata _blsPublicKey,
        string calldata _ticker,
        address _stakehouse,
        uint256 _savETHIndexId,
        IDataStructures.ETH2DataReport calldata _eth2Report,
        IDataStructures.EIP712Signature calldata _reportSignature
    ) external pure {
        revert("TransactionRouterMock: Not implemented");
    }

    function rageQuitPostDeposit(
        address _user,
        bytes calldata _blsPublicKey,
        address _stakehouse,
        IDataStructures.ETH2DataReport calldata _eth2Report,
        IDataStructures.EIP712Signature calldata _reportSignature
    ) external pure {
        revert("TransactionRouterMock: Not implemented");
    }
}
