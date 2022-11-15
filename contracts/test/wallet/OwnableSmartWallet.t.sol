// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableSmartWallet} from "../../OwnableSmartWallet.sol";
import {IOwnableSmartWalletEvents} from "../../interfaces/IOwnableSmartWallet.sol";

import "../lib/test.sol";
import {CheatCodes, HEVM_ADDRESS} from "../lib/cheatCodes.sol";

import {RAY, LENDER, BORROWER, DUMB_ADDRESS} from "../lib/constants.sol";
import {ExecutableMock} from "../mocks/ExecutableMock.sol";

contract OwnableSmartWalletTest is DSTest, IOwnableSmartWalletEvents {
    CheatCodes evm = CheatCodes(HEVM_ADDRESS);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    OwnableSmartWallet wallet;
    ExecutableMock callableContract;

    function setUp() public {
        wallet = new OwnableSmartWallet();
        wallet.initialize(LENDER);

        callableContract = new ExecutableMock();
    }

    /// @dev [OSW-1]: Initializer sets correct owner and can't be called twice
    function test_OSW_01_initializer_sets_correct_value_and_can_be_called_once()
        public
    {
        assertEq(wallet.owner(), LENDER, "Wallet owner incorrect");

        evm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        wallet.initialize(DUMB_ADDRESS);
    }

    /// @dev [OSW-2]: setApproval sets value correctly, emits event and reverts on non-owner
    function test_OSW_02_setApproval_has_access_control_and_sets_value_correctly()
        public
    {
        evm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(LENDER, BORROWER, true);

        evm.prank(LENDER);
        wallet.setApproval(BORROWER, true);

        assertTrue(
            wallet.isTransferApproved(LENDER, BORROWER),
            "Value was not set"
        );

        evm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(LENDER, BORROWER, false);

        evm.prank(LENDER);
        wallet.setApproval(BORROWER, false);

        assertTrue(
            !wallet.isTransferApproved(LENDER, BORROWER),
            "Value was not set"
        );
    }

    /// @dev [OSW-2A]: setApproval reverts on zero-address
    function test_OSW_02A_setApproval_reverts_on_zero_to_address() public {
        evm.expectRevert(
            bytes("OwnableSmartWallet: Approval cannot be set for zero address")
        );
        evm.prank(LENDER);
        wallet.setApproval(address(0), true);
    }

    /// @dev [OSW-3]: isTransferApproved returns true for same address
    function test_OSW_03_isTransferApproved_returns_true_for_same_address()
        public
    {
        assertTrue(
            wallet.isTransferApproved(LENDER, LENDER),
            "Transfer not approved from address to itself"
        );
    }

    /// @dev [OSW-4]: transferOwnership reverts unless owner or approved address calls
    function test_OSW_04_transferOwnership_reverts_unless_authorized() public {
        evm.expectRevert(bytes("OwnableSmartWallet: Transfer is not allowed"));
        evm.prank(BORROWER);
        wallet.transferOwnership(BORROWER);
    }

    /// @dev [OSW-5]: transferOwnership works for owner/approvedAddress, sets correct value and emits event
    function test_OSW_05_transferOwnership_is_correct() public {
        evm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(LENDER, BORROWER);

        evm.prank(LENDER);
        wallet.transferOwnership(BORROWER);

        assertEq(wallet.owner(), BORROWER, "Owner was not set correctly");

        evm.prank(BORROWER);
        wallet.setApproval(LENDER, true);

        evm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(BORROWER, LENDER, false);

        evm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(BORROWER, DUMB_ADDRESS);

        evm.prank(LENDER);
        wallet.transferOwnership(DUMB_ADDRESS);

        assertEq(wallet.owner(), DUMB_ADDRESS, "Owner was not set correctly");

        assertTrue(
            !wallet.isTransferApproved(BORROWER, LENDER),
            "Approval was not removed"
        );
    }

    /// @dev [OSW-6]: execute passes correct data to correct contract
    function test_OSW_06_execute_is_correct() public {
        evm.deal(LENDER, 2000);

        evm.expectCall(address(callableContract), "foo");

        evm.prank(LENDER);
        wallet.execute{value: 1000}(address(callableContract), "foo");

        assertEq(
            string(callableContract.getCallData()),
            "foo",
            "Incorrect calldata was passed"
        );

        assertEq(
            callableContract.getValue(),
            1000,
            "Incorrect value was passed"
        );

        evm.prank(LENDER);
        wallet.execute{value: 1000}(address(callableContract), "foobar", 250);

        assertEq(
            string(callableContract.getCallData()),
            "foobar",
            "Incorrect calldata was passed"
        );

        assertEq(
            callableContract.getValue(),
            250,
            "Incorrect value was passed"
        );

        evm.prank(LENDER);
        wallet.execute(address(callableContract), "foobar");

        assertEq(callableContract.getValue(), 0, "Incorrect value was passed");
    }

    /// @dev [OSW-6A]: execute reverts for non-owner
    function test_OSW_06A_execute_reverts_for_non_owner() public {
        evm.expectRevert(bytes("Ownable: caller is not the owner"));
        evm.prank(BORROWER);
        wallet.execute(address(callableContract), "foo");

        evm.expectRevert(bytes("Ownable: caller is not the owner"));
        evm.prank(BORROWER);
        wallet.execute(address(callableContract), "foo", 1000);
    }
}
