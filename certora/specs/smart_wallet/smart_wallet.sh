certoraRun contracts/test/mocks/OwnableSmartWalletMock.sol \
    --verify OwnableSmartWalletMock:certora/specs/smart_wallet/smart_wallet.spec \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "Smart Wallet" \
    --send_only \
    --rule_sanity basic \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin
