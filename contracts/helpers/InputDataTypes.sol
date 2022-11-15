pragma solidity ^0.8.10;

import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";

struct InitialsRegisterInputs {
    bytes[] _blsPublicKey;
    bytes[] _blsSignature;
}

struct DepositInputs {
    bytes[] _blsPublicKey;
    bytes[] _ciphertext;
    bytes[] _aesEncryptorKey;
    IDataStructures.EIP712Signature[] _encryptionSignature;
    bytes32[] _dataRoot;
}

struct StakehouseJoinInputs {
    address _stakehouse;
    uint256 _brandTokenId;
    bytes[] _blsPublicKey;
    IDataStructures.ETH2DataReport[] _eth2Report;
    IDataStructures.EIP712Signature[] _reportSignature;
}

library CorrectnessChecks {
    function checkCorrectness(InitialsRegisterInputs memory inputs)
        internal
        pure
    {
        require(
            (inputs._blsPublicKey.length == inputs._blsSignature.length),
            "InitialsRegisterInputs: Data length mismatch"
        );
    }

    function checkCorrectness(DepositInputs memory inputs) internal pure {
        require(
            (inputs._blsPublicKey.length == inputs._ciphertext.length) &&
                (inputs._ciphertext.length == inputs._aesEncryptorKey.length) &&
                (inputs._aesEncryptorKey.length ==
                    inputs._encryptionSignature.length) &&
                (inputs._encryptionSignature.length == inputs._dataRoot.length),
            "DepositInputs: Data length mismatch"
        );
    }

    function checkCorrectness(StakehouseJoinInputs memory inputs)
        internal
        pure
    {
        require(
            (inputs._blsPublicKey.length == inputs._eth2Report.length) &&
                (inputs._eth2Report.length == inputs._reportSignature.length),
            "StakehouseJoinInputs: Data length mismatch"
        );
    }
}
