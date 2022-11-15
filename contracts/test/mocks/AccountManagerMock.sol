// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IAccountManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IAccountManager.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";

interface IAccountManagerMock is IAccountManager {
    function recordAccountData(
        address depositor,
        bytes memory blsPublicKey,
        bytes memory blsSignature
    ) external;

    function recordDepositStatus(bytes memory blsPublicKey) external;

    function depositIsProcessed(bytes calldata _blsPublicKey)
        external
        view
        returns (bool);
}

contract AccountManagerMock is IAccountManagerMock {
    struct DepositStatus {
        bool depositStarted;
        uint256 startTS;
    }

    mapping(bytes => IDataStructures.Account) accountData;
    mapping(bytes => DepositStatus) depositStatus;

    function getAccountByPublicKey(bytes calldata _blsPublicKey)
        external
        view
        returns (IDataStructures.Account memory)
    {
        return accountData[_blsPublicKey];
    }

    function areInitialsRegistered(bytes calldata _blsPublicKey)
        external
        view
        returns (bool)
    {
        return (accountData[_blsPublicKey].depositor != address(0));
    }

    function depositIsProcessed(bytes calldata _blsPublicKey)
        external
        view
        returns (bool)
    {
        return
            (depositStatus[_blsPublicKey].depositStarted) &&
            (block.timestamp - depositStatus[_blsPublicKey].startTS >=
                3600 * 24);
    }

    function recordAccountData(
        address depositor,
        bytes memory blsPublicKey,
        bytes memory blsSignature
    ) external {
        accountData[blsPublicKey] = IDataStructures.Account({
            depositor: depositor,
            blsSignature: blsSignature,
            depositBlock: 0
        });
    }

    function recordDepositStatus(bytes memory blsPublicKey) external {
        depositStatus[blsPublicKey] = DepositStatus({
            depositStarted: true,
            startTS: block.timestamp
        });

        accountData[blsPublicKey].depositBlock =
            block.timestamp +
            3600 *
            24 *
            7;
    }

    function isKeyDeposited(bytes calldata _blsPublicKey)
        external
        pure
        returns (bool)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function blsPublicKeyToLifecycleStatus(bytes calldata _blsPublicKey)
        external
        pure
        returns (IDataStructures.LifecycleStatus)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function claimedTokens(bytes calldata _blsPublicKey)
        external
        pure
        returns (bool)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function getAccount(uint256 _index)
        external
        pure
        returns (IDataStructures.Account memory)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function getDepositBlock(bytes calldata _blsPublicKey)
        external
        view
        returns (uint256)
    {
        return accountData[_blsPublicKey].depositBlock;
    }

    function getLastKnownActiveBalance(bytes calldata _blsPublicKey)
        external
        pure
        returns (uint64)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function getLastKnownStateByPublicKey(bytes calldata _blsPublicKey)
        external
        pure
        returns (IDataStructures.ETH2DataReport memory)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function getLastReportEpoch(bytes calldata _blsPublicKey)
        external
        pure
        returns (uint64)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function getSignatureByBLSKey(bytes calldata _blsPublicKey)
        external
        pure
        returns (bytes memory)
    {
        revert("AccountManagerMock: Not implemented");
    }

    function numberOfAccounts() external pure returns (uint256) {
        revert("AccountManagerMock: Not implemented");
    }
}
