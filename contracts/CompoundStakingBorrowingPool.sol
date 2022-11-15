// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IBorrowingPool, DebtPosition, LenderPosition} from "./interfaces/IBorrowingPool.sol";
import {IInterestRateModel} from "./interfaces/IInterestRateModel.sol";
import {RAY, SECONDS_PER_YEAR} from "./helpers/Constants.sol";

/// @title Compound staking strategy borrowing pool
/// @notice Implements a borrowing pool used to provide
///         liquidity for depositors that wan't to obtain
///         staking power with leverage. Accepts ETH as liquidity,
///         but debts are repaid in DETH after the depositor mints
///         their derivatives. DETH can be swapped to ETH on open market, if needed.
contract CompoundStakingBorrowingPool is AccessControl, ERC20, IBorrowingPool {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @dev Identifier for the CompoundStakingStrategy role
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    /// @dev Identifier for the Configurator (owner) role
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @dev DETH token address
    address public immutable deth;

    /// @dev Address of the interest rate model
    address public interestRateModel;

    /// @dev Amount of ETH liquidity that was not yet spent to acquire DETH
    uint256 public assumedLiquidity;

    /// @dev Amount of ETH liquidity currently in the pool
    uint256 public availableLiquidity;

    /// @dev Amount of DETH per single pool share, multiplied by RAY
    uint256 public currentCumulativeDethPerShare_RAY;

    /// @dev The latest recorded interest index, in RAY format
    uint256 public interestIndexLU_RAY;

    /// @dev Timestamp of the latest interest index update
    uint256 public timestampLU;

    /// @dev Minimal size of deposit
    uint256 public minDepositLimit = 1 ether / 10;

    /// @dev Whether this contract is deprecated and cannot accept new deposits
    bool public isDeprecated;

    /// @dev Map from lender address to their data
    mapping(address => LenderPosition) public lenders;

    /// @dev Map from debtor address the their data
    mapping(address => DebtPosition) public debtors;

    /// @param _deth Address of the DETH token
    /// @param _interestRateModel Address of the interest rate model
    /// @param _name Name of the pool's share ERC20
    /// @param _symbol Symbol of the pool's share ERC20
    constructor(
        address _deth,
        address _interestRateModel,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_deth != address(0));

        deth = _deth; // F: [CSBP-1]
        interestRateModel = _interestRateModel; // F: [CSBP-1]

        interestIndexLU_RAY = RAY; // F: [CSBP-1]
        timestampLU = block.timestamp; // F: [CSBP-1]

        _grantRole(CONFIGURATOR_ROLE, msg.sender); // F: [CSBP-1]
        _setRoleAdmin(STRATEGY_ROLE, CONFIGURATOR_ROLE); // F: [CSBP-1]
    }

    // MODIFIERS
    // -------------------------

    /// @dev Updates the current cumulative interest index
    ///      before executing the function the function
    /// @notice Must be called before all functions that modify
    ///         assumed or available liquidity, since the borrow
    ///         rate will change afterwards
    modifier withIndexUpdate() {
        _updateIndex();
        _;
    }

    /// @dev Updates the accrued rewards amount and cumulative reward per token
    ///      for a lender before executing the function
    /// @notice Must be called before all functions that modify the
    ///         lender's share balance
    modifier withLenderUpdate(address lender) {
        _updateLenderPosition(lender);
        _;
    }

    /// @dev Reverts if a function is called when the contract is deprecated
    modifier whenNotDeprecated() {
        require(
            !isDeprecated,
            "BorrowingPool: Action unavailable when deprecated"
        );
        _;
    }

    // LP DEPOSITS & WITHDRAWALS
    // -------------------------

    /// @dev Deposits ETH into the pool and mints pool shares to sender
    /// @notice Modifies both the lender's balance and the interest rate,
    ///         so index and lender's cumulative reward per token have
    ///         to be updated
    function deposit()
        external
        payable
        whenNotDeprecated // F: [CSBP-12]
        withIndexUpdate // F: [CSBP-14]
        withLenderUpdate(msg.sender) // F: [CSBP-15]
    {
        uint256 amount = msg.value; // F: [CSBP-3,4]

        require(
            amount >= minDepositLimit,
            "BorrowingPool: Attempting to deposit less than the minimal deposit amount"
        ); // F: [CSBP-2]

        // In theory, a scenario may be reached when assumedLiquidity == 0
        // but there are outstanding shares (i.e. when the entire pool was
        // borrowed and then repaid, without any new deposits). In this
        // case, new deposits are impossible due to division by zero. Therefore,
        // a minimal assumed liquidity amount has to be established. The depositor
        // will lose an amount to existing shareholders, but it will be negligible.

        uint256 assumedLiquidityAdj = assumedLiquidity < 1e12
            ? 1e12 // F: [CSBP-4A]
            : assumedLiquidity;

        uint256 shares = totalSupply() == 0
            ? amount // F: [CSBP-3]
            : (amount * totalSupply()) / assumedLiquidityAdj; // F: [CSBP-4]

        assumedLiquidity += amount; // F: [CSBP-3,4]
        availableLiquidity += amount; // F: [CSBP-3,4]

        _mint(msg.sender, shares); // F: [CSBP-3,4]
        emit ETHDeposited(msg.sender, amount); // F: [CSBP-3,4]
    }

    /// @dev Burns shares from the sender and return the equivalent fraction
    ///      of remaining ETH liquidity. Optionally, sends all DETH accrued
    ///      by the lender.
    /// @param shares The amount of shares to burn
    /// @param claim Whether to claim accrued DETH
    /// @notice Modifies both the lender's balance and the interest rate,
    ///         so index and lender's cumulative reward per token have
    ///         to be updated
    function withdraw(uint256 shares, bool claim)
        external
        withIndexUpdate // F: [CSBP-14]
        withLenderUpdate(msg.sender) // F: [CSBP-15]
    {
        uint256 amount = (shares * assumedLiquidity) / totalSupply(); // F: [CSBP-8]

        require(
            availableLiquidity >= amount,
            "BorrowingPool Withdraw: Not enough cash available"
        );

        _burn(msg.sender, shares); // F: [CSBP-8]

        assumedLiquidity -= amount; // F: [CSBP-8]
        availableLiquidity -= amount; // F: [CSBP-8]

        if (claim) {
            _claimDETH(msg.sender); // F: [CSBP-8]
        }

        payable(msg.sender).transfer(amount); // F: [CSBP-8]
        emit ETHWithdrawn(msg.sender, amount); // F: [CSBP-8]
    }

    /// @dev Claims all of the accrued DETH for the lender
    ///      and sends it to the lender's address
    /// @param lender Lender to claim for
    /// @notice While this doesn't modify the lender balance,
    ///         the position is updated to record
    ///         the latest reward amount beforehand
    function claimDETH(address lender)
        external
        withLenderUpdate(lender) // F: [CSBP-15]
    {
        _claimDETH(lender);
    }

    /// @dev Claims all of the accrued DETH for msg.sender
    ///      and sends it to the msg.sender's address
    /// @notice While this doesn't modify the sender's balance,
    ///         the position is updated to record
    ///         the latest reward amount beforehand
    function claimDETH()
        external
        withLenderUpdate(msg.sender) // F: [CSBP-15]
    {
        _claimDETH(msg.sender);
    }

    /// @dev IMPLEMENTATION: claimDETH
    /// @param lender The address to claim for
    function _claimDETH(address lender) internal {
        uint256 amount = lenders[lender].dethEarned;
        lenders[lender].dethEarned = 0;

        IERC20(deth).safeTransfer(lender, amount);
        emit DETHClaimed(lender, amount);
    }

    // IBorrowingPool
    // --------------

    /// @dev Borrows ETH from the pool and records the debt to
    ///      the debtor's address
    /// @param debtor The address to create a debt position for
    /// @param amount The debt principal to borrow
    /// @param recipient Address to send ETH to
    /// @notice Can only be called by the strategy, since the pool
    ///         itself does not enforce repayment and only strategy
    ///         can do that. As such, the debt will be
    ///         recorded to the address of the strategy.
    /// @notice This function changes the available liquidity,
    ///         so the index has to update beforehand. Also, the
    ///         cumulative index at debt opening is recorded,
    ///         so the index must be up to date, to correctly
    ///         compute interest for the debtor
    function borrow(
        address debtor,
        uint256 amount,
        address recipient
    )
        external
        whenNotDeprecated // F: [CSBP-12]
        onlyRole(STRATEGY_ROLE) // F: [CSBP-13]
        withIndexUpdate // F: [CSBP-14]
    {
        // A single debtor can only have one debt position,
        // since the pool also does not take additional debt
        // for a debtor before finishing the full lifecycle
        // and repaying the debt
        require(
            !debtors[debtor].isCurrentlyDebtor,
            "BorrowingPool Borrow: Debtor has outstanding debt"
        );

        _borrow(debtor, amount, recipient);
    }

    /// @dev IMPLEMENTATION: borrow
    /// @param debtor The address to create a debt position for
    /// @param amount The debt principal to borrow
    /// @param recipient Address to send ETH to
    function _borrow(
        address debtor,
        uint256 amount,
        address recipient
    ) internal {
        require(
            availableLiquidity >= amount,
            "BorrowingPool Borrow: Not enough ETH to borrow from"
        ); // F: [CSBP-6]

        // The function records the last observed
        // interest index into the position
        // Debt interest is not stored, and is
        // instead computed dynamically based on
        // the proportion of current index to
        // index at opening

        debtors[debtor] = DebtPosition({
            isCurrentlyDebtor: true,
            principalAmount: amount,
            interestIndexAtOpen_RAY: interestIndexLU_RAY
        }); // F: [CSBP-5]

        /// Requirement above ensures the underflow protection
        unchecked {
            availableLiquidity -= amount; // F: [CSBP-5]
        }

        payable(recipient).sendValue(amount); // F: [CSBP-5]

        emit Borrowed(debtor, amount); // F: [CSBP-5]
    }

    /// @dev Repays a debt position for a particular debtor in DETH,
    ///      with implied 1 : 1 ETH-to-DETH exchange rate.
    /// @param debtor Debtor to repay the debt for
    /// @param amount The repaid amount
    /// @param loss Shortfall due to the debtor not having
    ///             enough funds to cover principal + interest.
    ///             Passed and added to the event for informational
    ///             purposes only.
    /// @notice The acquired DETH and ETH liquidity decrease are both split
    ///         among current lenders pro-rata shares.
    /// @notice Can only be called by the strategy. The pool trusts the strategy
    ///         to correctly compute the repaid amount and enforce repayment.
    /// @notice Updates the assumed liquidity, so the index has to be updated
    ///         beforehand.
    function repay(
        address debtor,
        uint256 amount,
        uint256 loss
    )
        external
        onlyRole(STRATEGY_ROLE) // F: [CSBP-13]
        withIndexUpdate // F: [CSBP-14]
    {
        _repay(debtor, amount, loss);
    }

    /// @dev IMPLEMENTATION: repay
    /// @param debtor Debtor to repay the debt for
    /// @param amount The repaid amount
    /// @param loss Shortfall due to the debtor not having
    ///             enough funds to cover principal + interest.
    ///             Passed and added to the event for informational
    ///             purposes only.
    function _repay(
        address debtor,
        uint256 amount,
        uint256 loss
    ) internal {
        IERC20(deth).safeTransferFrom(debtor, address(this), amount); // F: [CSBP-6]

        currentCumulativeDethPerShare_RAY += (amount * RAY) / totalSupply(); // F: [CSBP-6]

        assumedLiquidity -= debtors[debtor].principalAmount; // F: [CSBP-6]

        // The pool trusts the strategy to compute the repaid
        // amount, so it doesn't run any checks on the passed value,
        // and simply closes the entire debt position
        delete debtors[debtor];

        emit Repaid(debtor, amount, loss); // F: [CSBP-6]
    }

    /// @dev Returns the current total debt, including interest,
    ///      for a particular debtor
    /// @param debtor The address to compute debt for. Must have an
    ///               existing debt position.
    /// @return Amount of DETH owed to the pool
    function getBorrowAmountWithInterest(address debtor)
        external
        view
        returns (uint256)
    {
        require(
            debtors[debtor].isCurrentlyDebtor,
            "BorrowingPool: Address is not an active debtor"
        );

        return
            (debtors[debtor].principalAmount * _getCurrentIndex()) /
            debtors[debtor].interestIndexAtOpen_RAY; // F: [CSBP-16]
    }

    /// @dev Returns the expected interest accrued over a duration,
    ///      assuming interest rate doesn't change after the initial borrow
    /// @param principalAmount The debt principal to compute
    ///                        interest for
    /// @param duration Expected duration of a debt position
    /// @return Expected interest amount in DETH
    function getExpectedInterest(uint256 principalAmount, uint256 duration)
        external
        view
        returns (uint256)
    {
        require(
            availableLiquidity >= principalAmount,
            "BorrowingPool: Requested principal amount exceeds available liquidity"
        );

        return
            (principalAmount *
                _getInterestRate(
                    assumedLiquidity,
                    availableLiquidity - principalAmount
                ) *
                duration) / (SECONDS_PER_YEAR * RAY); // F: [CSBP-17]
    }

    /// @dev Returns data for a particular debtor
    /// @param debtor Address to return the struct for
    function getDebtor(address debtor)
        external
        view
        returns (DebtPosition memory)
    {
        return debtors[debtor];
    }

    /// @dev Returns data for a particular lender
    /// @param lender Address to return the struct for
    function getLender(address lender)
        external
        view
        returns (LenderPosition memory)
    {
        return lenders[lender];
    }

    // ERC20
    // ------------------

    /// @dev Transfers pool shares to another address
    /// @param to Address to transfer shares to
    /// @param amount Amount of shares to transfer
    /// @notice This function modifies the sender's
    ///         and the recipient's share balances,
    ///         so positions of both must be updated
    function transfer(address to, uint256 amount)
        public
        override
        withLenderUpdate(msg.sender) // F: [CSBP-15]
        withLenderUpdate(to) // F: [CSBP-15]
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers pool shares from one address to another
    /// @param from Address to transfer shares from
    /// @param to Address to transfer shares to
    /// @param amount Amount of shares to transfer
    /// @notice This function modifies the sender's
    ///         and the recipient's share balances,
    ///         so positions of both must be updated
    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override
        withLenderUpdate(from) // F: [CSBP-15]
        withLenderUpdate(to) // F: [CSBP-15]
        returns (bool)
    {
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    // Yield calculations
    // ------------------

    /// @dev Retrieves the current interest rate from the model,
    ///      based on assumed (total) and available liquidity
    /// @param _assumedLiquidity Assumed liquidity to compute interest rate
    /// @param _availableLiquidity Available liquidity to compute interest rate
    function _getInterestRate(
        uint256 _assumedLiquidity,
        uint256 _availableLiquidity
    ) internal view returns (uint256) {
        return
            IInterestRateModel(interestRateModel).getInterestRate(
                _assumedLiquidity,
                _availableLiquidity
            );
    }

    /// @dev Calculates the interest index at this moment
    /// @notice The index is computed as
    ///         currentIndex = indexLU * (1 + annualRate * timeSinceLU / SECONDS_PER_YEAR)
    ///         I.e., the index grows multiplicatively
    function _getCurrentIndex() internal view returns (uint256) {
        return
            (interestIndexLU_RAY *
                (RAY +
                    ((_getInterestRate(assumedLiquidity, availableLiquidity) *
                        (block.timestamp - timestampLU)) / SECONDS_PER_YEAR))) /
            RAY;
    }

    /// @dev Sets the recorded index value to the most current index
    ///      and updates the timestamp.
    /// @notice This must always be done immediately before a
    ///         change in interest rate, as otherwise the new
    ///         interest rate will be erroneously applied to the
    ///         entire period since last update
    function _updateIndex() internal {
        interestIndexLU_RAY = _getCurrentIndex();
        timestampLU = block.timestamp;
    }

    /// @dev Updates the DETH amount pending to the lender, and their
    ///      last recorded cumulative reward per share.
    /// @notice This must always be done immediately before a change in
    ///         lender's balance, as otherwise the old cumulative rewards
    ///         diff will be erroneously applied to the new balance
    function _updateLenderPosition(address lender) internal {
        uint256 newReward = ((currentCumulativeDethPerShare_RAY -
            lenders[lender].cumulativeDethPerShareLU_RAY) * balanceOf(lender)) /
            RAY;

        lenders[lender]
            .cumulativeDethPerShareLU_RAY = currentCumulativeDethPerShare_RAY;
        lenders[lender].dethEarned += newReward;
    }

    // Configuration
    // ------------------

    /// @dev Sets a new interest rate calculator
    /// @notice Restricted to configurator only
    function setNewInterestRateModel(address newInterestRateModel)
        external
        onlyRole(CONFIGURATOR_ROLE) // F: [CSBP-9]
    {
        interestRateModel = newInterestRateModel; // F: [CSBP-9]
    }

    /// @dev Sets a new deposit limit
    /// @notice Restricted to configurator only
    function setMinDepositLimit(uint256 newMinDepositLimit)
        external
        onlyRole(CONFIGURATOR_ROLE) // F: [CSBP-10]
    {
        minDepositLimit = newMinDepositLimit; // F: [CSBP-10]
    }

    /// @dev Transfers the configurator role to another address
    /// @notice Restricted to configurator only.
    /// @notice Caution! The action is irreversible and can lead to loss
    ///         of control if the new address is wrong.
    function setConfigurator(address newConfigurator)
        external
        onlyRole(CONFIGURATOR_ROLE) // F: [CSBP-11]
    {
        _grantRole(CONFIGURATOR_ROLE, newConfigurator); // F: [CSBP-11]
        _revokeRole(CONFIGURATOR_ROLE, msg.sender); // F: [CSBP-11]
    }

    /// @dev Deprecates the contract disabling new deposits and borrows
    /// @notice There is a quirk in pool mathematics that can cause
    ///         uncontrolled totalSupply() growth when the pool is drained
    ///         and subsequently deposited to often. E.g.:
    ///         Suppose that 1 ETH is initially deposited into the pool and
    ///         0.5 ETH is borrowed and repaid. The first depositor has 1e18 shares
    ///         if a new depositor brings 1 ETH, 2e18 shares will be minted. If this
    ///         is repeated many times, total supply and minted shares amounts can get
    ///         to untenable levels. In this case, the strategy / pool complex can be
    ///         deprecated by calling this function, which will prevent new deposits
    ///         and borrows, and a new one can be deployed.
    /// @notice Restricted to configurator only
    function deprecate()
        external
        onlyRole(CONFIGURATOR_ROLE) // F: [CSBP-12]
    {
        isDeprecated = true; // F: [CSBP-12]
    }
}
