// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableSmartWallet} from "../../OwnableSmartWallet.sol";
import {OwnableSmartWalletFactory} from "../../OwnableSmartWalletFactory.sol";
import {IOwnableSmartWallet} from "../../interfaces/IOwnableSmartWallet.sol";
import {IOwnableSmartWalletFactoryEvents} from "../../interfaces/IOwnableSmartWalletFactory.sol";

import "../lib/test.sol";
import {CheatCodes, HEVM_ADDRESS} from "../lib/cheatCodes.sol";

import {RAY, LENDER, BORROWER, DUMB_ADDRESS} from "../lib/constants.sol";
import {ExecutableMock} from "../mocks/ExecutableMock.sol";

contract OwnableSmartWalletFactoryTest is
    DSTest,
    IOwnableSmartWalletFactoryEvents
{
    CheatCodes evm = CheatCodes(HEVM_ADDRESS);

    OwnableSmartWalletFactory factory;
    address targetWallet;

    event TestEvent(address indexed addr);

    function setUp() public {
        factory = new OwnableSmartWalletFactory();
    }

    /// @dev [OSWF-1]: createWallet creates new wallet correctly and emits events
    function test_OSWF_01_createWallet_correctly_clones_wallet_and_emits_event()
        public
    {
        evm.expectEmit(false, true, false, false);
        emit WalletCreated(address(0), LENDER);

        evm.prank(LENDER);
        address newWallet = factory.createWallet();

        assertEq(
            IOwnableSmartWallet(newWallet).owner(),
            LENDER,
            "Owner is not correct"
        );

        evm.expectEmit(false, true, false, false);
        emit WalletCreated(address(0), BORROWER);

        newWallet = factory.createWallet(BORROWER);

        assertEq(
            IOwnableSmartWallet(newWallet).owner(),
            BORROWER,
            "Owner is not correct"
        );
    }

    /// @dev [OSWF-2]: constructor creates correct contract and fires event
    function test_OSWF_02_constructor_is_correct() public {
        evm.expectEmit(false, false, false, false);
        emit WalletCreated(address(0), address(0));

        OwnableSmartWalletFactory newFactory = new OwnableSmartWalletFactory();

        assertEq(
            OwnableSmartWallet(newFactory.masterWallet()).owner(),
            address(newFactory),
            "New factoty master wallet owner incorrect"
        );
    }
}
