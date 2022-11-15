methods {
    getPositionTimestamp(address) returns uint40 envfree;
    getCurrentBlockTime() returns uint40;
    getInitiator(address) returns address envfree;
    getPositionStatus(address) returns uint8 envfree;
    getNumberOfKnots(address) returns uint16 envfree;
    getContractBalance() returns uint256;
    getBorrowingPoolBalance() returns uint256;

    borrow(address,uint256,address) => DISPATCHER(true)
    getExpectedInterest(uint256, uint256) => DISPATCHER(true)
}

rule positionTimestampOnlyIncreases(method f, env e) {
    address wallet;
    uint40 timestamp = getCurrentBlockTime(e);
    uint40 posBefore = getPositionTimestamp(wallet);

    calldataarg d;
    f(e, d);

    assert getPositionTimestamp(wallet) != posBefore => getPositionTimestamp(wallet) >= timestamp;
}

rule initiatorIsZeroWhenInactiveOrUnused(method f, env e) {
    address wallet;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address initiator = getInitiator(wallet);

    require getInitiator(wallet) == ZERO <=> getPositionStatus(wallet) <= 1;

    calldataarg d;
    f(e, d);

    assert getInitiator(wallet) == ZERO <=> getPositionStatus(wallet) <= 1;
}

rule knotCountIsZeroWhenInactiveOrUnused(method f, env e) {
    address wallet;
    uint16 ZERO = 0;

    require getNumberOfKnots(wallet) == ZERO <=> getPositionStatus(wallet) <= 1;

    calldataarg d;
    f(e, d);

    assert getNumberOfKnots(wallet) == ZERO <=> getPositionStatus(wallet) <= 1;
}

rule pendingPositionOnlyIncreasesOrReset(method f, env e) {

    address wallet;
    uint8 positionBefore = getPositionStatus(wallet);

    calldataarg d;
    f(e, d);

    uint8 positionAfter = getPositionStatus(wallet);

    assert positionAfter >= positionBefore || positionAfter == 1;
}

function getExpectedStatus(uint8 currentStatus) returns uint8 {
    if (currentStatus == 3) {
        uint8 result = 1;
        return result;
    }

    uint8 result = currentStatus + 1;

    return result;
}


rule onlyDepositWithLeverageCanSetDepositedStatus(method f, env e) {
    address wallet;
    uint8 positionBefore = getPositionStatus(wallet);

    calldataarg d;
    f(e, d);

    uint8 positionAfter = getPositionStatus(wallet);

    assert positionBefore != positionAfter => getExpectedStatus(positionBefore) == positionAfter;
}

rule fundingConservesETHBalance(env e) {
    uint256 nKnots;
    uint256 fundedValue;
    address wallet;

    uint256 beforeSum = getContractBalance(e) + getBorrowingPoolBalance(e);

    fundKnots(e, nKnots, fundedValue, wallet);

    uint256 afterSum = getContractBalance(e) + getBorrowingPoolBalance(e);

    assert beforeSum == afterSum;
}
