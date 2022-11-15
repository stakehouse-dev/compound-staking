# Stakehouse protocol Compound Staking

A suite of contracts to stake with leverage in the Stakehouse protocol.

Compound staking allows users to create KNOTs on borrowed funds, which enables them to obtain a validator in Stakehouse with as little as ~8 ETH. The user keeps their SLOT after minting the derivatives, while dETH goes towards repaying their debt.

## Borrowing pool

`CompoundStakingBorrowingPool.sol` implements a contract that sources liquidity for borrowing.

### Overview

Lenders deposit ETH through `deposit()` and receive a number of shares pro-rata the size of their deposit relative to current total liquidity ("assumed liquidity").

Only the compound staking strategy contract can borrow and repay loans. The strategy borrows ETH and repays the principal + interest in dETH (the implied exchange rate is 1 ETH = 1 dETH). This means that assumed liquidity in ETH decreases over time, while all incoming dETH is distributed to users pro-rata their shares, with a Master Chef-like mechanism.

On calling `withdraw()`, the user receives a part of remaining assumed liquidity pro-rata their shares, as well as all dETH that accrued to their account.

### Interest accrual

Interest on debt accrues through a multiplicatively growing index. On each index update (this happens on any liquidity-affecting transaction), the index is updated as `newIndex = currentIndex * (1 + interestAnnual(utilization) * timeElapsedLU / secondsPerYear)`, where `timeElapsedLU` is time in seconds since last index update, `interestAnnual(utilization)` is a function of interest from the rate of utilization of pool funds. 

Total borrowed amount for a debtor is computed as `principal * (indexNow / indexAtOpen)`.

### Share economy details

Due to total/assumed ETH liquidity decreasing with borrows, there are some mathematical quirks with share computations in the borrowing pool:

1) In an edge case, the entire pool may be drained with borrows, which would decrease assumed liquidity to 0. This can lead to a division by 0 or very small numbers in share computations, since shares are minted based on ratio of deposit size to current liquidity. To address this, the pool computes assumed liquidity as `max(assumedLiquidity, 10^-6 ETH)` (i.e., there is a small minimal boundary for liquidity). This means that a depositor into a drained pool would give a fraction of their deposit to existing shareholders, but this quantity is negligibly small.

2) Since liquidity decreases over time but existing share balances stay the same, liquidity refills in the pool would mint progressively more shares. E.g., if half the liquidity in the pool is drained, then twice more shares will be minted to the same amount of ETH deposited, compared to pool creation. This can lead to share amounts becoming untenable over time - a deprecation mechanism exists that stops all new deposits and borrows and allows to migrate liquidity to a new pool.

## Compound staking strategy

The strategy is the main contract that implements leveraged staking. 

### Overview

The general lifecycle of a position in a strategy is as follows:
1) The user creates a transferrable smart wallet (this can be done through a factory or by just passing `address(0)` to the strategy function) and registers it with the strategy through `CompoundStakingStrategy.registerSmartWallet()`. This is required to collateralize the user's position before derivatives are minted and the debt is repaid - KNOTs are not transferrable by default.
2) The user submits a batch of validator initials to the strategy, to register with Stakehouse. The credentials are registered with the wallet as the depositor. The wallet ownership is transferred to the strategy and it becomes inaccessible to the user directly.
3) Once credentials are registered, the user can call `depositFromWalletWithLeverage()` with an ETH value to batch-deposit for all registered initials. The value can be less than `32 * number of credentials`, which enables leverage. The strategy will compute the shortfall and borrow it from the pool. The strategy will check that the minted dETH will be enough to cover the borrowed amount + projected interest with a sufficient buffer. Deposit processing on the Consensus Chain typically takes 24 hours, while the strategy ensures that at least 72 hours worth of interest are covered.
4) Once all deposits are processed (this is ensured by Stakehouse requiring ETH2 balance reports to be submitted for each credential), the user can call `joinStakehouseAndRepay`. The pending KNOTs will batch-join a particular stakehouse, the derivatives will be minted and the debt will be repaid. The smart wallet owning the KNOTs will be returned to the user, including all leftover dETH after repaying the debt. This ends the lifecycle.

### Loss

If after minting all derivativers there is not enough dETH on the smart wallet to repay the current debt amount, the strategy will simply send all dETH to the pool and record a loss.

This should be exceedingly rare due to a generous buffer to cover interest, but is still possible in some cases (e.g., if a position becomes stuck, see below).

### Liquidations

Only the user that originally initiated the lifecycle can call `joinStakehouseAndRepay`. While the user is incentivized to mint the derivatives and repay the debt as soon as possible (since otherwise their KNOTs will remain frozen and interest will continue accruing), in some cases (e.g., the original initiator loses access to keys) a position can become stuck, preventing repayment of debt to the pool.

After a grace period (30 days by default), the position will become liquidatable - a designated liquidator address can force the execution of the last step with any stakehouse of their choice, and send the wallet to any recipient. The exact mechanism of liquidation is outside the scope of this contract suite.

## Tests

Tests use Foundry Forge. [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation).

To run tests, use:

`yarn test`