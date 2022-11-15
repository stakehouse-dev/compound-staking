// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IInterestRateModel {
    function getInterestRate(
        uint256 assumedLiquidity,
        uint256 availableLiquidity
    ) external view returns (uint256);
}
