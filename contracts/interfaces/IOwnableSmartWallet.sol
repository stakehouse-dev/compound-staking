// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IOwnableSmartWalletEvents {
    event TransferApprovalChanged(
        address indexed from,
        address indexed to,
        bool status
    );
}

interface IOwnableSmartWallet is IOwnableSmartWalletEvents {
    function initialize(address initialOwner) external;

    function execute(address target, bytes memory callData)
        external
        payable
        returns (bytes memory);

    function execute(
        address target,
        bytes memory callData,
        uint256 value
    ) external payable returns (bytes memory);

    function transferOwnership(address newOwner) external;

    function setApproval(address to, bool status) external;

    function isTransferApproved(address from, address to)
        external
        view
        returns (bool);

    function owner() external view returns (address);
}
