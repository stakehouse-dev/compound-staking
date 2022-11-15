// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @dev Struct containing information on a particular lender address
struct LenderPosition {
    uint256 cumulativeDethPerShareLU_RAY;
    uint256 dethEarned;
}

/// @dev Struct containing information on a particular debtor address
struct DebtPosition {
    bool isCurrentlyDebtor;
    uint256 principalAmount;
    uint256 interestIndexAtOpen_RAY;
}

interface IBorrowingPoolEvents {
    /// @dev Emitted when ETH is deposited to the pool
    event ETHDeposited(address indexed depositor, uint256 amount);

    /// @dev Emitted when ETH is withdrawn from the pool
    event ETHWithdrawn(address indexed depositor, uint256 amount);

    /// @dev Emitted when DETH rewards are claimed for a depositor
    event DETHClaimed(address indexed depositor, uint256 amount);

    /// @dev Emitted when the strategy borrows ETH for a wallet
    event Borrowed(address indexed borrower, uint256 amount);

    /// @dev Emitted when a debt position is repaid
    event Repaid(address indexed borrower, uint256 amount, uint256 loss);
}

interface IBorrowingPool is IBorrowingPoolEvents {
    function borrow(
        address debtor,
        uint256 amount,
        address recipient
    ) external;

    function repay(
        address debtor,
        uint256 amount,
        uint256 loss
    ) external;

    function getBorrowAmountWithInterest(address debtor)
        external
        view
        returns (uint256);

    function getExpectedInterest(uint256 principalAmount, uint256 duration)
        external
        view
        returns (uint256);

    function getDebtor(address debtor)
        external
        view
        returns (DebtPosition memory);

    function getLender(address lender)
        external
        view
        returns (LenderPosition memory);
}
