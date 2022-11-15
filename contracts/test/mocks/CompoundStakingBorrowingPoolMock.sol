pragma solidity ^0.8.10;

import { CompoundStakingBorrowingPool } from "../../CompoundStakingBorrowingPool.sol";
import { IInterestRateModel } from "../../interfaces/IInterestRateModel.sol";

contract CompoundStakingBorrowingPoolMock is CompoundStakingBorrowingPool {

    IInterestRateModel model;

    constructor (
        address _deth,
        address _interestRateModel,
        string memory _name,
        string memory _symbol
    ) CompoundStakingBorrowingPool(_deth, _interestRateModel, _name, _symbol) {
        model = IInterestRateModel(_interestRateModel);
    }

    function getDebtorStatus(address _debtor) external view returns (bool) {
        return debtors[_debtor].isCurrentlyDebtor;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function hasConfiguratorRole(address _user) external view returns (bool) {
        return hasRole(CONFIGURATOR_ROLE, _user);
    }

    function getDETHEarnedByLender(address _lender) external view returns (uint256) {
        return lenders[_lender].dethEarned;
    }

    function getCummulativeDETHPerShareLender(address _lender) external view returns (uint256) {
      return lenders[_lender].cumulativeDethPerShareLU_RAY;
    }

    function getAddress() external view returns (address) {
        return address(this);
    }
}