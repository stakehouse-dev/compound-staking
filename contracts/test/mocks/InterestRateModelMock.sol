// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {RAY} from "../../helpers/Constants.sol";

contract InterestRateModelMock {
    uint256 public immutable interestRateRAY0;
    uint256 public immutable interestRateRAY1;
    uint256 public immutable breakpoint;

    constructor(
        uint256 interestRateValueRAY0,
        uint256 interestRateValueRAY1,
        uint256 _breakpoint
    ) {
        interestRateRAY0 = interestRateValueRAY0;
        interestRateRAY1 = interestRateValueRAY1;
        breakpoint = _breakpoint;
    }

    function getInterestRate(
        uint256 assumedLiquidity,
        uint256 availableLiquidity
    ) external view returns (uint256) {
        if (assumedLiquidity == 0) {
            return interestRateRAY0;
        }

        return
            (availableLiquidity * RAY) / assumedLiquidity > breakpoint
                ? interestRateRAY0
                : interestRateRAY1;
    }
}
