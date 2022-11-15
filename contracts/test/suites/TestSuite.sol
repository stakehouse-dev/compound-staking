// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { OwnableSmartWalletFactory } from "../../OwnableSmartWalletFactory.sol";

import {AccountManagerMock} from "../mocks/AccountManagerMock.sol";
import {SavETHManagerMock} from "../mocks/SavETHManagerMock.sol";
import {TransactionRouterMock} from "../mocks/TransactionRouterMock.sol";
import {UniswapV3Mock} from "../mocks/UniswapV3Mock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {WETHMock} from "../mocks/WETHMock.sol";

import {RAY} from "../../helpers/Constants.sol";

contract CompoundStakingTestSuite {

    OwnableSmartWalletFactory public factory;

    AccountManagerMock public amMock;
    SavETHManagerMock public semMock;
    TransactionRouterMock public trMock;

    ERC20Mock public deth;

    constructor() {

        factory = new OwnableSmartWalletFactory();

        deth = new ERC20Mock("Degenerate ETH", "DETH", 18);

        amMock = new AccountManagerMock();
        semMock = new SavETHManagerMock(address(deth), address(amMock));
        trMock = new TransactionRouterMock(address(amMock), address(semMock));
    }
}
