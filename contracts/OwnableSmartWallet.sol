// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IOwnableSmartWallet} from "./interfaces/IOwnableSmartWallet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title Ownable smart wallet
/// @notice Ownable and transferrable smart wallet that allows the owner to
///         interact with any contracts the same way as from an EOA. The
///         main intended use is to make non-transferrable positions and assets
///         liquid and usable in strategies.
/// @notice Intended to be used with a factory and the cloning pattern.
contract OwnableSmartWallet is IOwnableSmartWallet, Ownable, Initializable {
    using Address for address;

    /// @dev A map from owner and spender to transfer approval. Determines whether
    ///      the spender can transfer this wallet from the owner. Can be used
    ///      to put this wallet in possession of a strategy (e.g., as collateral).
    mapping(address => mapping(address => bool)) internal _isTransferApproved;

    /// @dev Initialization function used instead of a constructor,
    ///      since the intended creation method is cloning
    function initialize(address initialOwner)
        external
        override
        initializer // F: [OSW-1]
    {
        require(
            initialOwner != address(0),
            "OwnableSmartWallet: Attempting to initialize with zero address owner"
        );
        _transferOwnership(initialOwner); // F: [OSW-1]
    }

    /// @dev Makes an arbitrary function call with value to a contract, with provided calldata
    /// @param target Address of a contract to call
    /// @param callData Data to pass with the call
    /// @notice Payable. The passed value will be forwarded to the target.
    function execute(address target, bytes memory callData)
        external
        payable
        onlyOwner // F: [OSW-6A]
        returns (bytes memory)
    {
        return target.functionCallWithValue(callData, msg.value); // F: [OSW-6]
    }

    /// @dev Makes an arbitrary function call with value to a contract, with provided calldata and value
    /// @param target Address of a contract to call
    /// @param callData Data to pass with the call
    /// @param value ETH value to pass to the target
    /// @notice Payable. Allows the user to explicitly state the ETH value, in order to,
    ///         e.g., pay with the contract's own balance.
    function execute(
        address target,
        bytes memory callData,
        uint256 value
    )
        external
        payable
        onlyOwner // F: [OSW-6A]
        returns (bytes memory)
    {
        return target.functionCallWithValue(callData, value); // F: [OSW-6]
    }

    /// @dev Returns the current owner of the wallet
    function owner()
        public
        view
        override(IOwnableSmartWallet, Ownable)
        returns (address)
    {
        return Ownable.owner(); // F: [OSW-1]
    }

    /// @dev Transfers ownership from the current owner to another address
    /// @param newOwner The address that will be the new owner
    function transferOwnership(address newOwner)
        public
        override(IOwnableSmartWallet, Ownable)
    {
        // Only the owner themselves or an address that is approved for transfers
        // is authorized to do this
        require(
            isTransferApproved(owner(), msg.sender),
            "OwnableSmartWallet: Transfer is not allowed"
        ); // F: [OSW-4]

        // Approval is revoked, in order to avoid unintended transfer allowance
        // if this wallet ever returns to the previous owner
        if (msg.sender != owner()) {
            _setApproval(owner(), msg.sender, false); // F: [OSW-5]
        }
        _transferOwnership(newOwner); // F: [OSW-5]
    }

    /// @dev Changes authorization status for transfer approval from msg.sender to an address
    /// @param to Address to change allowance status for
    /// @param status The new approval status
    function setApproval(address to, bool status) external {
        require(
            to != address(0),
            "OwnableSmartWallet: Approval cannot be set for zero address"
        ); // F: [OSW-2A]
        _setApproval(msg.sender, to, status);
    }

    /// @dev IMPLEMENTATION: _setApproval
    /// @param from The owner address
    /// @param to The spender address
    /// @param status Status of approval
    function _setApproval(
        address from,
        address to,
        bool status
    ) internal {
        bool statusChanged = _isTransferApproved[from][to] != status;
        _isTransferApproved[from][to] = status; // F: [OSW-2]
        if (statusChanged) {
            emit TransferApprovalChanged(from, to, status); // F: [OSW-2]
        }
    }

    /// @dev Returns whether the address 'to' can transfer a wallet from address 'from'
    /// @param from The owner address
    /// @param to The spender address
    /// @notice The owner can always transfer the wallet to someone, i.e.,
    ///         approval from an address to itself is always 'true'
    function isTransferApproved(address from, address to)
        public
        view
        returns (bool)
    {
        return from == to ? true : _isTransferApproved[from][to]; // F: [OSW-2, 3]
    }
}
