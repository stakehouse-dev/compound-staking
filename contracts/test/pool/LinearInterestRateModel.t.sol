// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {LinearInterestRateModel} from "../../LinearInterestRateModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import "../lib/test.sol";
import {CheatCodes, HEVM_ADDRESS} from "../lib/cheatCodes.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {InterestRateModelMock} from "../mocks/InterestRateModelMock.sol";
import {CompoundStakingTestSuite} from "../suites/TestSuite.sol";

import {RAY, LENDER, BORROWER, DUMB_ADDRESS, DUMB_ADDRESS2, SECONDS_PER_YEAR} from "../lib/constants.sol";

contract LinearInterestRateModelTest is DSTest {
    CheatCodes evm = CheatCodes(HEVM_ADDRESS);

    LinearInterestRateModel model;

    /// @dev [LIRM-1]: Linear interest rate model fuzzed test
    function test_LIRM_01_fuzzed_test(
        uint256 baseRateRAY,
        uint256 optimalRateDiff,
        uint256 maxRateDiff,
        uint256 breakpointRAY,
        uint256 assumedLiquidity,
        uint256 availableLiquidity
    ) public {
        evm.assume(baseRateRAY > RAY / 100000);
        evm.assume(baseRateRAY <= RAY);
        evm.assume(optimalRateDiff <= RAY);
        evm.assume(maxRateDiff <= RAY);
        evm.assume(breakpointRAY <= RAY);
        evm.assume(assumedLiquidity < 10**40);
        evm.assume(availableLiquidity <= assumedLiquidity);

        breakpointRAY = breakpointRAY < 1000 ? 1000 : breakpointRAY;
        assumedLiquidity = assumedLiquidity < 1000 ? 1000: assumedLiquidity;

        model = new LinearInterestRateModel(
            baseRateRAY,
            baseRateRAY + optimalRateDiff,
            baseRateRAY + optimalRateDiff + maxRateDiff,
            breakpointRAY
        );

        uint256 utilizationExpected = (RAY *
            (assumedLiquidity - availableLiquidity)) / assumedLiquidity;

        uint256 belowOptimalPart = (optimalRateDiff *
                Math.min(utilizationExpected, breakpointRAY)) / breakpointRAY;

        uint256 aboveOptimalPart = utilizationExpected >= breakpointRAY ? (utilizationExpected - breakpointRAY) * maxRateDiff / (RAY - breakpointRAY) : 0;

        uint256 rateExpected = baseRateRAY +
            belowOptimalPart + aboveOptimalPart;

        assertEq(
            model.getInterestRate(assumedLiquidity, availableLiquidity),
            rateExpected,
            "Interest rate not calculated correctly"
        );
    }
}
