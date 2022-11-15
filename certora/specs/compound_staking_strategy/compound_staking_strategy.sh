certoraRun contracts/test/mocks/CompoundStakingStrategyMock.sol \
    contracts/CompoundStakingBorrowingPool.sol \
    --link CompoundStakingStrategyMock:borrowingPool=CompoundStakingBorrowingPool \
    --verify CompoundStakingStrategyMock:certora/specs/compound_staking_strategy/compound_staking_strategy.spec \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "Compound Strategy" \
    --send_only \
    --staging \
    --rule_sanity basic \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin
