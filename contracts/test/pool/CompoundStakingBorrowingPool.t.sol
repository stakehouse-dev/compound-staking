// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {CompoundStakingBorrowingPool} from "../../CompoundStakingBorrowingPool.sol";
import {IBorrowingPoolEvents} from "../../interfaces/IBorrowingPool.sol";

import "../lib/test.sol";
import {CheatCodes, HEVM_ADDRESS} from "../lib/cheatCodes.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {InterestRateModelMock} from "../mocks/InterestRateModelMock.sol";
import {CompoundStakingTestSuite} from "../suites/TestSuite.sol";

import {RAY, LENDER, BORROWER, DUMB_ADDRESS, DUMB_ADDRESS2, SECONDS_PER_YEAR} from "../lib/constants.sol";

contract BorrowingPoolTest is DSTest, IBorrowingPoolEvents {
    CheatCodes evm = CheatCodes(HEVM_ADDRESS);

    ERC20Mock deth;
    CompoundStakingBorrowingPool borrowingPool;

    address interestRateModel;

    function _accessControlError(address addr, bytes32 role)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(addr),
                    " is missing role ",
                    Strings.toHexString(uint256(role), 32)
                )
            );
    }

    function setUp() public {
        CompoundStakingTestSuite suite = new CompoundStakingTestSuite();

        deth = suite.deth();

        interestRateModel = address(
            new InterestRateModelMock(RAY / 20, RAY / 10, RAY / 2)
        );

        borrowingPool = new CompoundStakingBorrowingPool(
            address(deth),
            interestRateModel,
            "Compound Staking Pool Share",
            "shBPS"
        );

        borrowingPool.grantRole(borrowingPool.STRATEGY_ROLE(), address(this));
    }

    /// @dev [CSBP-1]: Constructor sets correct values
    function test_CSBP_01_constructor_sets_correct_values() public {
        assertEq(
            borrowingPool.name(),
            "Compound Staking Pool Share",
            "Pool ERC20 name incorrect"
        );

        assertEq(
            borrowingPool.symbol(),
            "shBPS",
            "Pool ERC20 symbol incorrect"
        );

        assertEq(
            borrowingPool.deth(),
            address(deth),
            "Pool DETH token incorrect"
        );

        assertEq(
            borrowingPool.interestRateModel(),
            interestRateModel,
            "Pool interest rate model incorrect"
        );

        assertTrue(
            borrowingPool.hasRole(borrowingPool.STRATEGY_ROLE(), address(this)),
            "Pool strategy role was not set correctly"
        );

        assertTrue(
            borrowingPool.hasRole(
                borrowingPool.CONFIGURATOR_ROLE(),
                address(this)
            ),
            "Pool configurator role was not set correctly"
        );

        assertEq(
            borrowingPool.getRoleAdmin(borrowingPool.STRATEGY_ROLE()),
            borrowingPool.CONFIGURATOR_ROLE(),
            "Configurator is not a strategy role admin"
        );
    }

    /// @dev [CSBP-2]: deposit reverts on deposit amount less than 0.1 ETH
    function test_CSBP_02_deposit_reverts_on_amount_too_low() public {
        evm.deal(LENDER, 1 ether);

        evm.expectRevert(
            "BorrowingPool: Attempting to deposit less than the minimal deposit amount"
        );
        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether / 20}();
    }

    /// @dev [CSBP-3]: deposit correctly updates values and emits event
    function test_CSBP_03_deposit_works_correctly(uint256 amount) public {
        evm.assume(amount > 1 ether / 10);
        evm.assume(amount < RAY);

        evm.deal(LENDER, amount);

        evm.expectEmit(true, false, false, true);
        emit ETHDeposited(LENDER, amount);

        evm.prank(LENDER);
        borrowingPool.deposit{value: amount}();

        assertEq(
            borrowingPool.balanceOf(LENDER),
            amount,
            "Initial shares balance incorrect"
        );

        assertEq(
            borrowingPool.assumedLiquidity(),
            amount,
            "Inital assumed liquidity incorrect"
        );

        assertEq(
            borrowingPool.availableLiquidity(),
            amount,
            "Initial available liquidity incorrect"
        );
    }

    /// @dev [CSBP-4]: subsequent deposit correctly updates values
    function test_CSBP_04_subsequent_deposit_works_correctly(
        uint256 amount1,
        uint256 amount2
    ) public {
        evm.assume(amount1 > 1 ether / 10);
        evm.assume(amount2 > 1 ether / 10);

        evm.assume(amount1 < RAY);
        evm.assume(amount2 < RAY);

        evm.deal(LENDER, amount1);

        evm.prank(LENDER);
        borrowingPool.deposit{value: amount1}();

        evm.deal(DUMB_ADDRESS, amount2);

        evm.prank(DUMB_ADDRESS);
        borrowingPool.deposit{value: amount2}();

        assertEq(
            borrowingPool.balanceOf(DUMB_ADDRESS),
            amount2,
            "Initial shares balance incorrect"
        );

        assertEq(
            borrowingPool.assumedLiquidity(),
            amount1 + amount2,
            "Inital assumed liquidity incorrect"
        );

        assertEq(
            borrowingPool.availableLiquidity(),
            amount1 + amount2,
            "Initial available liquidity incorrect"
        );
    }

    /// @dev [CSBP-4A]: subsequent deposit correctly updates values after the pool being fully drained
    function test_CSBP_04A_subsequent_deposit_zero_liquidity_works_correctly(
        uint256 amount1,
        uint256 amount2
    ) public {
        evm.assume(amount1 > 1 ether / 10);
        evm.assume(amount2 > 1 ether / 10);
        evm.assume(amount1 <= RAY);
        evm.assume(amount2 <= RAY);

        evm.deal(LENDER, amount1);

        evm.prank(LENDER);
        borrowingPool.deposit{value: amount1}();

        borrowingPool.borrow(DUMB_ADDRESS, amount1, DUMB_ADDRESS2);

        deth.mint(DUMB_ADDRESS, amount1);

        evm.prank(DUMB_ADDRESS);
        deth.approve(address(borrowingPool), type(uint256).max);

        borrowingPool.repay(DUMB_ADDRESS, amount1, 0);

        evm.deal(DUMB_ADDRESS, amount2);

        evm.prank(DUMB_ADDRESS);
        borrowingPool.deposit{value: amount2}();

        assertEq(
            borrowingPool.balanceOf(DUMB_ADDRESS),
            (amount2 * amount1) / 10**12,
            "Initial shares balance incorrect"
        );

        assertEq(
            borrowingPool.assumedLiquidity(),
            amount2,
            "Inital assumed liquidity incorrect"
        );

        assertEq(
            borrowingPool.availableLiquidity(),
            amount2,
            "Initial available liquidity incorrect"
        );
    }

    /// @dev [CSBP-5]: borrow correctly updates values and emits event
    function test_CSBP_05_borrow_works_correctly(
        uint256 depositAmount,
        uint256 borrowAmount
    ) public {
        evm.assume(depositAmount > 1 ether / 10);
        evm.assume(depositAmount <= RAY);
        evm.assume(borrowAmount <= depositAmount);

        evm.deal(LENDER, depositAmount);

        evm.prank(LENDER);
        borrowingPool.deposit{value: depositAmount}();

        evm.expectEmit(true, false, false, true);
        emit Borrowed(DUMB_ADDRESS, borrowAmount);

        borrowingPool.borrow(DUMB_ADDRESS, borrowAmount, DUMB_ADDRESS2);

        assertEq(
            payable(DUMB_ADDRESS2).balance,
            borrowAmount,
            "Recipient balance incorrect"
        );

        assertTrue(
            borrowingPool.getDebtor(DUMB_ADDRESS).isCurrentlyDebtor,
            "Debtor status was not updated"
        );

        assertEq(
            borrowingPool.getDebtor(DUMB_ADDRESS).principalAmount,
            borrowAmount,
            "Debtor principal amount incorrect"
        );

        assertEq(
            borrowingPool.getDebtor(DUMB_ADDRESS).interestIndexAtOpen_RAY,
            RAY,
            "Debtor principal amount incorrect"
        );

        assertEq(
            borrowingPool.availableLiquidity(),
            depositAmount - borrowAmount,
            "Available liquidity incorrect"
        );
    }

    /// @dev [CSBP-6]: borrow reverts on insufficient liquidity
    function test_CSBP_06_borrow_reverts_on_insufficient_liquidity() public {
        evm.deal(LENDER, 1 ether);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether}();

        evm.expectRevert("BorrowingPool Borrow: Not enough ETH to borrow from");
        borrowingPool.borrow(DUMB_ADDRESS, 3 ether / 2, DUMB_ADDRESS2);
    }

    /// @dev [CSBP-7]: repay correctly updates values and emits event
    function test_CSBP_07_repay_works_correctly(
        uint256 depositAmount,
        uint256 borrowAmount,
        uint256 repayAmount
    ) public {
        evm.assume(depositAmount > 1 ether / 10);
        evm.assume(depositAmount <= RAY);
        evm.assume(borrowAmount <= depositAmount);
        evm.assume(repayAmount <= RAY);

        evm.deal(LENDER, depositAmount);

        evm.prank(LENDER);
        borrowingPool.deposit{value: depositAmount}();

        borrowingPool.borrow(DUMB_ADDRESS, borrowAmount, DUMB_ADDRESS2);

        deth.mint(DUMB_ADDRESS, repayAmount);

        evm.prank(DUMB_ADDRESS);
        deth.approve(address(borrowingPool), type(uint256).max);

        evm.expectEmit(true, false, false, true);
        emit Repaid(DUMB_ADDRESS, repayAmount, 1 gwei);

        borrowingPool.repay(DUMB_ADDRESS, repayAmount, 1 gwei);

        assertEq(
            deth.balanceOf(DUMB_ADDRESS),
            0,
            "Incorrect deth balance of borrower"
        );

        assertEq(
            borrowingPool.currentCumulativeDethPerShare_RAY(),
            (repayAmount * RAY) / depositAmount,
            "Cumulative DETH per share incorrect"
        );

        assertEq(
            borrowingPool.assumedLiquidity(),
            depositAmount - borrowAmount,
            "Assumed liquidity incorrect"
        );

        assertTrue(
            !borrowingPool.getDebtor(DUMB_ADDRESS).isCurrentlyDebtor,
            "Debtor status not changed"
        );
    }

    /// @dev [CSBP-8]: withdraw works correctly and emits event
    function test_CSBP_08_withdraw_works_correctly(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 borrowAmount,
        uint256 repayAmount
    ) public {
        depositAmount1 = depositAmount1 % RAY;
        depositAmount1 = depositAmount1 < 1 ether / 10
            ? 1 ether / 10
            : depositAmount1;

        depositAmount2 = depositAmount2 % RAY;
        depositAmount2 = depositAmount2 < 1 ether / 10
            ? 1 ether / 10
            : depositAmount2;

        borrowAmount = borrowAmount % (depositAmount1 + depositAmount2);

        evm.assume(repayAmount < RAY);

        evm.deal(LENDER, depositAmount1);
        evm.deal(DUMB_ADDRESS, depositAmount2);

        evm.prank(LENDER);
        borrowingPool.deposit{value: depositAmount1}();

        evm.prank(DUMB_ADDRESS);
        borrowingPool.deposit{value: depositAmount2}();

        borrowingPool.borrow(BORROWER, borrowAmount, DUMB_ADDRESS2);

        deth.mint(BORROWER, repayAmount);

        evm.prank(BORROWER);
        deth.approve(address(borrowingPool), type(uint256).max);

        borrowingPool.repay(BORROWER, repayAmount, 0);

        uint256 totalDeposit = depositAmount1 + depositAmount2;
        uint256 shares = borrowingPool.balanceOf(LENDER);
        uint256 expectedAmount = ((totalDeposit - borrowAmount) * shares) /
            borrowingPool.totalSupply();
        uint256 expectedDETHAmount = (repayAmount * shares) /
            borrowingPool.totalSupply();

        evm.expectEmit(true, false, false, true);
        emit ETHWithdrawn(LENDER, expectedAmount);

        evm.prank(LENDER);
        borrowingPool.withdraw(shares, true);

        assertEq(
            payable(LENDER).balance,
            expectedAmount,
            "Incorrect ETH returned to lender"
        );

        assertLe(
            expectedDETHAmount - deth.balanceOf(LENDER),
            1,
            "Incorrect DETH returned to lender"
        );

        assertEq(
            borrowingPool.assumedLiquidity(),
            totalDeposit - expectedAmount - borrowAmount,
            "Incorrect leftover assumed liquidity"
        );

        assertEq(
            borrowingPool.availableLiquidity(),
            totalDeposit - expectedAmount - borrowAmount
        );
    }

    /// @dev [CSBP-9]: setNewInterestRateModel sets value and reverts on non-Configurator
    function test_CSBP_09_setNewInterestRateModel_works_correctly() public {
        evm.expectRevert(
            bytes(
                _accessControlError(BORROWER, borrowingPool.CONFIGURATOR_ROLE())
            )
        );
        evm.prank(BORROWER);
        borrowingPool.setNewInterestRateModel(DUMB_ADDRESS);

        borrowingPool.setNewInterestRateModel(DUMB_ADDRESS);

        assertEq(
            borrowingPool.interestRateModel(),
            DUMB_ADDRESS,
            "Interest rate model not set"
        );
    }

    /// @dev [CSBP-10]: setMinDepositLimit sets value and reverts on non-Configurator
    function test_CSBP_10_setMinDepositLimit_works_correctly() public {
        evm.expectRevert(
            bytes(
                _accessControlError(BORROWER, borrowingPool.CONFIGURATOR_ROLE())
            )
        );
        evm.prank(BORROWER);
        borrowingPool.setMinDepositLimit(1 ether);

        borrowingPool.setMinDepositLimit(1 ether);

        assertEq(
            borrowingPool.minDepositLimit(),
            1 ether,
            "Deposit limit not set"
        );
    }

    /// @dev [CSBP-11]: setConfigurator sets value and reverts on non-Configurator
    function test_CSBP_11_setConfigurator_works_correctly() public {
        evm.expectRevert(
            bytes(
                _accessControlError(BORROWER, borrowingPool.CONFIGURATOR_ROLE())
            )
        );
        evm.prank(BORROWER);
        borrowingPool.setConfigurator(DUMB_ADDRESS);

        borrowingPool.setConfigurator(DUMB_ADDRESS);

        assertTrue(
            borrowingPool.hasRole(
                borrowingPool.CONFIGURATOR_ROLE(),
                DUMB_ADDRESS
            ),
            "Configurator not changed"
        );
    }

    /// @dev [CSBP-12]: deprecate sets value and reverts on non-Configurator
    function test_CSBP_12_deprecate_works_correctly() public {
        evm.expectRevert(
            bytes(
                _accessControlError(BORROWER, borrowingPool.CONFIGURATOR_ROLE())
            )
        );
        evm.prank(BORROWER);
        borrowingPool.deprecate();

        borrowingPool.deprecate();

        assertTrue(borrowingPool.isDeprecated(), "Configurator not changed");

        evm.expectRevert("BorrowingPool: Action unavailable when deprecated");
        borrowingPool.borrow(DUMB_ADDRESS, 1, DUMB_ADDRESS);

        evm.expectRevert("BorrowingPool: Action unavailable when deprecated");
        borrowingPool.deposit();
    }

    /// @dev [CSBP-13]: borrow() and repay() revert on being called by non-Strategy
    function test_CSBP_13_strategy_restricted_functions_revert_on_wrong_caller()
        public
    {
        evm.expectRevert(
            bytes(_accessControlError(BORROWER, borrowingPool.STRATEGY_ROLE()))
        );
        evm.prank(BORROWER);
        borrowingPool.borrow(DUMB_ADDRESS, 1, DUMB_ADDRESS);

        evm.expectRevert(
            bytes(_accessControlError(BORROWER, borrowingPool.STRATEGY_ROLE()))
        );
        evm.prank(BORROWER);
        borrowingPool.repay(DUMB_ADDRESS, 1, 0);
    }

    /// @dev [CSBP-14]: withIndexUpdate() functions correctly update values
    function test_CSBP_14_withIndexUpdate_works_correctly() public {
        evm.warp(block.timestamp + SECONDS_PER_YEAR);

        evm.deal(LENDER, 1 ether);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether}();

        assertEq(
            borrowingPool.interestIndexLU_RAY(),
            (RAY * 105) / 100,
            "Borrow rate index incorrect"
        );

        assertEq(
            borrowingPool.timestampLU(),
            block.timestamp,
            "Timestamp LU incorrect"
        );

        evm.warp(block.timestamp + SECONDS_PER_YEAR);

        borrowingPool.borrow(DUMB_ADDRESS, 1, DUMB_ADDRESS2);

        assertEq(
            borrowingPool.interestIndexLU_RAY(),
            (RAY * 105**2) / 100**2,
            "Borrow rate index incorrect"
        );

        assertEq(
            borrowingPool.timestampLU(),
            block.timestamp,
            "Timestamp LU incorrect"
        );

        evm.warp(block.timestamp + SECONDS_PER_YEAR);

        borrowingPool.repay(DUMB_ADDRESS, 0, 0);

        assertEq(
            borrowingPool.interestIndexLU_RAY(),
            (RAY * 105**3) / 100**3,
            "Borrow rate index incorrect"
        );

        assertEq(
            borrowingPool.timestampLU(),
            block.timestamp,
            "Timestamp LU incorrect"
        );

        evm.warp(block.timestamp + SECONDS_PER_YEAR);

        evm.prank(LENDER);
        borrowingPool.withdraw(1 ether, false);

        assertEq(
            borrowingPool.interestIndexLU_RAY(),
            (RAY * 105**4) / 100**4,
            "Borrow rate index incorrect"
        );

        assertEq(
            borrowingPool.timestampLU(),
            block.timestamp,
            "Timestamp LU incorrect"
        );
    }

    /// @dev [CSBP-15]: withLenderUpdate() functions correctly update values
    function test_CSBP_15_withLenderUpdate_works_correctly() public {
        evm.deal(LENDER, 2 ether);
        deth.mint(DUMB_ADDRESS, RAY);
        evm.prank(DUMB_ADDRESS);
        deth.approve(address(borrowingPool), type(uint256).max);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether / 2}();

        borrowingPool.borrow(DUMB_ADDRESS, 0, DUMB_ADDRESS2);
        borrowingPool.repay(DUMB_ADDRESS, 1 ether, 0);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether / 2}();

        assertEq(
            borrowingPool.getLender(LENDER).cumulativeDethPerShareLU_RAY,
            2 * RAY,
            "Incorrect DETH per share"
        );

        assertEq(
            borrowingPool.getLender(LENDER).dethEarned,
            1 ether,
            "Incorrect DETH earned"
        );

        borrowingPool.borrow(DUMB_ADDRESS, 0, DUMB_ADDRESS2);
        borrowingPool.repay(DUMB_ADDRESS, 1 ether, 0);

        evm.prank(LENDER);
        borrowingPool.withdraw(1 ether / 2, false);

        assertEq(
            borrowingPool.getLender(LENDER).cumulativeDethPerShareLU_RAY,
            3 * RAY,
            "Incorrect DETH per share"
        );

        assertEq(
            borrowingPool.getLender(LENDER).dethEarned,
            2 ether,
            "Incorrect DETH earned"
        );

        borrowingPool.borrow(DUMB_ADDRESS, 0, DUMB_ADDRESS2);
        borrowingPool.repay(DUMB_ADDRESS, 1 ether, 0);

        evm.prank(LENDER);
        borrowingPool.transfer(DUMB_ADDRESS2, 1 ether / 2);

        evm.prank(DUMB_ADDRESS2);
        borrowingPool.approve(LENDER, type(uint256).max);

        assertEq(
            borrowingPool.getLender(LENDER).cumulativeDethPerShareLU_RAY,
            5 * RAY,
            "Incorrect DETH per share"
        );

        assertEq(
            borrowingPool.getLender(LENDER).dethEarned,
            3 ether,
            "Incorrect DETH earned"
        );

        borrowingPool.borrow(DUMB_ADDRESS, 0, DUMB_ADDRESS2);
        borrowingPool.repay(DUMB_ADDRESS, 1 ether, 0);

        evm.prank(LENDER);
        borrowingPool.transferFrom(DUMB_ADDRESS2, LENDER, 1 ether / 2);

        assertEq(
            borrowingPool.getLender(DUMB_ADDRESS2).cumulativeDethPerShareLU_RAY,
            7 * RAY,
            "Incorrect DETH per share"
        );

        assertEq(
            borrowingPool.getLender(DUMB_ADDRESS2).dethEarned,
            1 ether,
            "Incorrect DETH earned"
        );
    }

    /// @dev [CSBP-16]: getBorrowAmountWithInterest calculates the result correctly
    function test_CSBP_16_getBorrowAmountWithInterest_works_correctly(
        uint256 timeElapsed1,
        uint256 timeElapsed2
    ) public {
        evm.assume(timeElapsed1 < SECONDS_PER_YEAR * 100);
        evm.assume(timeElapsed2 < SECONDS_PER_YEAR * 100);

        evm.deal(LENDER, 1 ether);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether}();

        evm.warp(block.timestamp + timeElapsed1);

        borrowingPool.borrow(DUMB_ADDRESS, 1 ether, DUMB_ADDRESS2);

        evm.warp(block.timestamp + timeElapsed2);

        uint256 diff;
        uint256 expectedAmount = (1 ether * (RAY + ((RAY / 10) * timeElapsed2) / SECONDS_PER_YEAR)) /
                RAY;

        if (borrowingPool.getBorrowAmountWithInterest(DUMB_ADDRESS) >= expectedAmount) {
            diff = borrowingPool.getBorrowAmountWithInterest(DUMB_ADDRESS) - expectedAmount;
        } else {
            diff = expectedAmount - borrowingPool.getBorrowAmountWithInterest(DUMB_ADDRESS);
        }
        
        assertLe(
            diff,
            1
        );
    }

        /// @dev [CSBP-17]: getExpectedInterest calculates the result correctly
    function test_CSBP_17_getExpectedInterest_works_correctly(
        uint256 timeElapsed
    ) public {

        evm.assume(timeElapsed < SECONDS_PER_YEAR * 100);

        evm.deal(LENDER, 1 ether);

        evm.prank(LENDER);
        borrowingPool.deposit{value: 1 ether}();

        assertEq(
            borrowingPool.getExpectedInterest(1 ether / 10, timeElapsed),
            1 ether / 10 * (RAY / 20 * timeElapsed / SECONDS_PER_YEAR) / RAY
        );

        assertEq(
            borrowingPool.getExpectedInterest(1 ether, timeElapsed),
            1 ether * (RAY / 10 * timeElapsed / SECONDS_PER_YEAR) / RAY
        );
    }
}
