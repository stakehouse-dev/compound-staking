pragma solidity ^0.8.13;

import { OwnableSmartWallet } from "../../OwnableSmartWallet.sol";

contract OwnableSmartWalletMock is OwnableSmartWallet {

    function getApproveMapping(address _from, address _to) external view returns (bool) {
        return _isTransferApproved[_from][_to];
    }

}