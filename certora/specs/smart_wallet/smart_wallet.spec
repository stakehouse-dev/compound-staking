methods {
    isTransferApproved(address,address) returns bool envfree;
    getApproveMapping(address,address) returns bool envfree;
    owner() returns address envfree;
}

rule transferImpliesApproval(env e) {
    address ownerBefore = owner();
    address recipient;
    address sender;

    require recipient != 0x0000000000000000000000000000000000000000;
    require e.msg.sender == sender;

    bool wasApproved = isTransferApproved(ownerBefore, sender);

    transferOwnership(e, recipient);

    assert owner() == recipient && wasApproved;
}

rule onlyRenounceAndTransferCanChangeOwnerhsip(method f, env e)
filtered {
    f -> f.selector != initialize(address).selector
}
{
    address ownerBefore = owner();

    calldataarg d;
    f(e, d);

    assert owner() != ownerBefore => f.selector == transferOwnership(address).selector || f.selector == renounceOwnership().selector;
}

rule onlyOneFunctionCanSetApproval(method f, env e)
filtered {
    f -> f.selector != initialize(address).selector &&
         f.selector != transferOwnership(address).selector
}
{
    address owner = owner();
    address recipient;
    address sender;

    bool approvalBefore = getApproveMapping(sender, recipient);

    calldataarg d;
    f(e, d);

    assert getApproveMapping(sender, recipient) != approvalBefore => f.selector == setApproval(address,bool).selector;
}