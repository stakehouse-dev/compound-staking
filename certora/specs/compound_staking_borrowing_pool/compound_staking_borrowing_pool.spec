using LinearInterestRateModel as linearModel

methods {
    timestampLU() returns uint256;
    assumedLiquidity() returns uint256 envfree;
    availableLiquidity() returns uint256 envfree;
    getDebtorStatus(address) returns bool envfree;
    totalSupply() returns uint256 envfree;
    balanceOf(address) returns uint256 envfree;
    interestIndexLU_RAY() returns uint256 envfree;
    getTimestamp() returns uint256;

    getInterestRate(uint256,uint256) returns uint256 envfree => DISPATCHER(true);
    linearModel.getInterestRate(uint256,uint256) returns uint256 envfree;

    interestRateModel() returns address envfree;

    hasConfiguratorRole(address) returns bool envfree;

    minDepositLimit() returns uint256 envfree;

    isDeprecated() returns bool envfree;

    getDETHEarnedByLender(address) returns uint256 envfree;

    currentCumulativeDethPerShare_RAY() returns uint256 envfree;

    getCummulativeDETHPerShareLender(address) returns uint256 envfree;

    getBalance() returns uint256 envfree;

    getAddress() returns address envfree;
}

rule globalTimeOnlyIncreases(method f, env e) {
    uint256 T1 = timestampLU(e);

    calldataarg d;
    f(e, d);

    assert timestampLU(e) >= T1;
}

rule onlyBorrowCanSetDebtorStatusToTrue(method f, env e) {

    address debtor;
    bool status = getDebtorStatus(debtor);

    require status == false;

    calldataarg d;
    f(e, d);

    assert status == true => f.selector == borrow(address,uint256,address).selector;
}

rule onlyRepayCanSetDebtorStatusToFalse(method f, env e) {
    address debtor;
    bool status = getDebtorStatus(debtor);

    require status == true;

    calldataarg d;
    f(e, d);

    assert status == false => f.selector == repay(address,uint256,uint256).selector;
}

function getExpectedIncrease(uint256 assumedLiq, uint256 total, uint256 amount) returns uint256 {
    uint256 minAssumedLiq = 1000000000000;

    if (total == 0) {
        return amount;
    }

    if (assumedLiq < minAssumedLiq) {
        uint256 result = (amount * total) / minAssumedLiq;

        return result;
    }

    uint256 result = (amount * total) / assumedLiq;

    return result;
}

rule shareMintingRulesHold(env e) {
    uint256 total = totalSupply();
    uint256 assumedLiq = assumedLiquidity();
    uint256 balanceBefore = balanceOf(e.msg.sender);

    deposit(e);

    assert balanceOf(e.msg.sender) - balanceBefore == getExpectedIncrease(assumedLiq, total, e.msg.value);
}

function computeExpectedIndexRAY(uint256 assumedLiq, uint256 availableLiq, uint256 blockTimestamp, env e) returns uint256 {
    uint256 interestRate = linearModel.getInterestRate(assumedLiq, availableLiq);
    uint256 timeDelta = blockTimestamp - timestampLU(e);
    uint256 timeInterestProduct = interestRate * timeDelta;
    uint256 secondsPerYear = 365 * 24 * 60 * 60;
    uint256 RAY = 1000000000000000000000000000;

    uint256 currentIndex = interestIndexLU_RAY();

    uint256 annualRateAdjustedRay = timeInterestProduct / secondsPerYear + RAY;

    uint256 result = (currentIndex * annualRateAdjustedRay) / RAY;

    return result;
}

rule indexRateChangesObeysDescription(env e, method f) {
    uint256 oldIndexRay = interestIndexLU_RAY();

    uint256 assumedLiq = assumedLiquidity();
    uint256 availableLiquidity = availableLiquidity();
    uint256 timestamp = getTimestamp(e);

    calldataarg d;
    f(e, d);

    uint256 newIndexRay = interestIndexLU_RAY();

    assert newIndexRay != oldIndexRay => newIndexRay == computeExpectedIndexRAY(assumedLiq, availableLiquidity, timestamp, e);
}

rule onlyConfiguratorCanChangeInterestRateModel(env e, method f)
filtered {
    f -> !f.isView && !f.isPure
}
{

    address modelOld = interestRateModel();

    calldataarg d;
    f(e, d);

    assert modelOld != interestRateModel() => hasConfiguratorRole(e.msg.sender);
}

rule onlyConfiguratorCanChangeMinDeposit(env e, method f)
filtered {
    f -> !f.isView && !f.isPure
}
{
    uint256 oldMinDeposit = minDepositLimit();

    calldataarg d;
    f(e, d);

    assert oldMinDeposit != minDepositLimit() => hasConfiguratorRole(e.msg.sender);
}

rule onlyConfiguratorCanDeprecate(env e, method f)
filtered {
    f -> !f.isView && !f.isPure
}
{
    require isDeprecated() == false;

    calldataarg d;
    f(e, d);

    assert isDeprecated() == true => hasConfiguratorRole(e.msg.sender);
}

function computedETHDelta(address lender) returns uint256 {
    uint256 currentCumulativeDETHPerShare = currentCumulativeDethPerShare_RAY();
    uint256 lenderCumulativeDETHPerShare = getCummulativeDETHPerShareLender(lender);

    uint256 RAY = 1000000000000000000000000000;

    uint256 cummulativeDelta = currentCumulativeDETHPerShare - lenderCumulativeDETHPerShare;
    uint256 result = (cummulativeDelta * balanceOf(lender)) / RAY;

    return result;
}

rule onlyAllowedMethodsCanDecreaseETHBalance(env e, method f)
filtered {
    f -> !f.isView && !f.isPure
}
{
    uint256 balanceBefore = getBalance();

    calldataarg d;
    f(e, d);

    uint256 balanceAfter = getBalance();

    assert balanceAfter < balanceBefore => f.selector == borrow(address,uint256,address).selector || f.selector == withdraw(uint256,bool).selector;
}