// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import {IAccountManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IAccountManager.sol";
import {IERC20Mock} from "./ERC20Mock.sol";
import {DETH_MINTED_AMOUNT} from "../../helpers/Constants.sol";

interface ISavETHManagerMock is ISavETHManager {
    function prepareDETHForKNOT(address _stakehouse, bytes memory _blsPublicKey)
        external;
}

contract SavETHManagerMock is ISavETHManagerMock {
    mapping(address => mapping(bytes => bool)) knotPendingDETH;
    IERC20Mock public deth;
    IAccountManager accountManager;

    uint256 currentIndexId = 0;

    constructor(address _deth, address _accountManager) {
        deth = IERC20Mock(_deth);
        accountManager = IAccountManager(_accountManager);
    }

    function prepareDETHForKNOT(address _stakehouse, bytes memory _blsPublicKey)
        external
    {
        knotPendingDETH[_stakehouse][_blsPublicKey] = true;
    }

    function addKnotToOpenIndexAndWithdraw(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        address _recipient
    ) external {
        require(
            msg.sender ==
                accountManager.getAccountByPublicKey(_blsPublicKey).depositor,
            "SavETHManagerMock: Sender is not authorized to spend KNOT"
        );
        deth.mint(_recipient, DETH_MINTED_AMOUNT);
        knotPendingDETH[_stakeHouse][_blsPublicKey] = false;
    }

    function createIndex(address _owner) external returns (uint256) {
        return ++currentIndexId;
    }

    function approveForIndexOwnershipTransfer(
        uint256 _indexId,
        address _spender
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function approveSpendingOfKnotInIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        address _spender
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function approvedIndexSpender(uint256 _indexId)
        external
        pure
        returns (address)
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function approvedKnotSpender(bytes calldata _blsPublicKey)
        external
        pure
        returns (address)
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function associatedIndexIdForKnot(bytes calldata _blsPublicKey)
        external
        pure
        returns (uint256)
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function dETHInCirculation() external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function dETHRewardsMintedForKnot(bytes calldata _blsPublicKey)
        external
        pure
        returns (uint256)
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function dETHToSavETH(uint256 _amount) external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function dETHToken() external pure returns (address) {
        revert("SavETHManagerMock: Not implemented");
    }

    function dETHUnderManagementInOpenIndex() external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function deposit(address _recipient, uint128 _amount) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function depositAndIsolateKnotIntoIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        uint256 _indexId
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function indexIdToOwner(uint256 _indexId) external pure returns (address) {
        revert("SavETHManagerMock: Not implemented");
    }

    function isKnotPartOfOpenIndex(bytes calldata _blsPublicKey)
        external
        pure
        returns (bool)
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function isolateKnotFromOpenIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        uint256 _targetIndexId
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function knotDETHBalanceInIndex(
        uint256 _indexId,
        bytes calldata _blsPublicKey
    ) external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function savETHToDETH(uint256 _amount) external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function savETHToken() external pure returns (address) {
        revert("SavETHManagerMock: Not implemented");
    }

    function totalDETHInIndices() external pure returns (uint256) {
        revert("SavETHManagerMock: Not implemented");
    }

    function transferIndexOwnership(uint256 _indexId, address _to)
        external
        pure
    {
        revert("SavETHManagerMock: Not implemented");
    }

    function transferKnotToAnotherIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        uint256 _newIndexId
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function addKnotToOpenIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey,
        address _recipient
    ) external pure {
        revert("SavETHManagerMock: Not implemented");
    }

    function withdraw(address _recipient, uint128 _amount) external pure {
        revert("SavETHManagerMock: Not implemented");
    }
}
