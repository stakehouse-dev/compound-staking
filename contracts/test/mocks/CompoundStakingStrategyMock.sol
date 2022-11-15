pragma solidity ^0.8.10;

import { CompoundStakingStrategy } from "../../CompoundStakingStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CompoundStakingStrategyMock is CompoundStakingStrategy {

    constructor(
        address _factory,
        address _borrowingPool,
        address _transactionRouter,
        address _savETHManager,
        address _accountManager,
        address _deth
    ) CompoundStakingStrategy(_factory, _borrowingPool, _transactionRouter, _savETHManager, _accountManager, _deth) {}

    function getPositionTimestamp(address _wallet) view external returns (uint40) {
        return pendingPositions[_wallet].timestampLU;
    }

    function getCurrentBlockTime() view external returns (uint40) {
        return uint40(block.timestamp);
    }

    function getInitiator(address _wallet) view external returns (address) {
        return pendingPositions[_wallet].initiator;
    }

    function getPositionStatus(address _wallet) view external returns (uint8) {
        return uint8(pendingPositions[_wallet].status);
    }

    function getNumberOfKnots(address _wallet) view external returns (uint16) {
        return pendingPositions[_wallet].nKnots;
    }

    function fundKnots(uint256 _nKnots, uint256 _fundedValue, address _wallet) external {
        _fundExtraKnots(_nKnots, _fundedValue, _wallet);
    }

    function getContractBalance() external returns (uint256) {
        return address(this).balance;
    }

    function getBorrowingPoolBalance() external returns (uint256) {
        return address(borrowingPool).balance;
    }

    function isDebtCleared(address _wallet) external returns (bool) {
        bool condition1 = borrowingPool.getDebtor(_wallet).isCurrentlyDebtor;
        bool condition2 = borrowingPool.getDebtor(_wallet).principalAmount == 0;
        bool condition3 = borrowingPool.getDebtor(_wallet).interestIndexAtOpen_RAY == 0;

        return condition1 && condition2 && condition3;
    }

    function getdETHBalance(address _wallet) public view returns (uint256) {
        return IERC20(deth).balanceOf(_wallet);
    }

    function getBorrowingPooldETHBalance() external view returns (uint256) {
        return getdETHBalance(address(borrowingPool));
    }

    function repayDebtToPool(address _wallet) external {
        _repayDebtToPool(_wallet);
    }
}