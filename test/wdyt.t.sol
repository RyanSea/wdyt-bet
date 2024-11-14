// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import "forge-std/interfaces/IERC20.sol";

import "src/wdyt.sol";
import "solady/utils/ERC1967Factory.sol";
import "test/mock/MockUSDB.sol";
import { Ownable } from "solady/auth/Ownable.sol";   

contract WDYTTest is Test {
    WDYT wdyt;
    ERC1967Factory factory;

    MockUSDB usdb;

    address owner = makeAddr('owner');
    address bettorYes1 = makeAddr('bettorYes1');
    address bettorYes2 = makeAddr('bettorYes2');
    address bettorNo1 = makeAddr('bettorNo1');
    address bettorNo2 = makeAddr('bettorNo2');

    function setUp() public {
        factory = new ERC1967Factory();
        usdb = new MockUSDB();
        address wdyt_logic = address(new WDYT(address(usdb)));

        wdyt = WDYT(factory.deployAndCall(
            wdyt_logic,
            owner,
            abi.encodeCall(WDYT.initialize, (owner))
        ));

        usdb.mint(bettorYes1, 100_000 ether);
        usdb.mint(bettorYes2, 100_000 ether);
        usdb.mint(bettorNo1, 100_000 ether);
        usdb.mint(bettorNo2, 100_000 ether);
    }

    function test_WDYT() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(bettorYes1);
        wdyt.createMarket("test", 2, block.timestamp + 1 hours);

        vm.expectEmit(true, true, true, true, address(wdyt));
        emit WDYT.MarketCreated({
            id: 1,
            description: "test",
            telegram: 2,
            deadline: block.timestamp + 1 hours
        });
        vm.prank(owner);
        uint id = wdyt.createMarket("test", 2, block.timestamp + 1 hours);

        uint bettorBalBefore = usdb.balanceOf(bettorYes1);
        uint protocolBalBefore = usdb.balanceOf(address(wdyt));

        vm.expectEmit(true, true, true, true, address(wdyt));
        emit WDYT.BetMade({
            id: id,
            bettor: bettorYes1,
            outcome: true,
            amount: 25 ether,
            shares: wdyt.calcShares(id, true, 25 ether)
        });
        vm.prank(bettorYes1);
        uint shares1 = wdyt.bet(id, true, 25 ether);

        assertEq(bettorBalBefore - usdb.balanceOf(bettorYes1), 25 ether, "WRONG BALANCE: BETTOR");
        assertEq(usdb.balanceOf(address(wdyt)) - protocolBalBefore, 25 ether, "WRONG BALANCE: PROTOCOL");

        vm.prank(bettorYes2);
        uint shares2 = wdyt.bet(id, true, 25 ether);

        console.log(shares1);
        console.log(shares2);

        assertTrue(shares1 > shares2, "NO BONDING CURVE");

        vm.prank(bettorNo1);
        uint shares3 = wdyt.bet(id, false, 25 ether);

        assertEq(shares1, shares3, "ASYMMETRIC SHARES");

        vm.startPrank(bettorNo2);
        wdyt.bet(id, false, 40 ether);

        vm.expectRevert("NOT_RESOLVER");
        wdyt.resolveMarket(id, true);

        vm.startPrank(owner);
        vm.expectRevert("DEADLINE_NOT_PASSED");
        wdyt.resolveMarket(id, true);

        vm.warp(block.timestamp + 1 hours);
        vm.expectEmit(true, true, true, true, address(wdyt));
        emit WDYT.MarketResolved({
            id: id,
            outcome: true
        });
        wdyt.resolveMarket(id, true);

        vm.expectRevert("MARKET_ALREADY_RESOLVED"); 
        wdyt.resolveMarket(id, false);

        vm.startPrank(bettorYes1);
        vm.expectRevert("MARKET_CLOSED");
        wdyt.bet(id, true, 5 ether);

        WDYT.MarketData memory data = wdyt.getMarket(id);

        assertTrue(data.resolved, "INCORRECT_RESOLVED");
        assertTrue(data.outcome, "INCORRECT_OUTCOME");

        uint totalAssets = data.noBets;

        uint expectedPayout = (shares1 * totalAssets) / data.totalYesShares;
        uint initialBet = wdyt.getBet(id, bettorYes1).yesBets;

        vm.expectEmit(true, true, true, true, address(wdyt));
        emit WDYT.BetRedeemed({
            id: id,
            bettor: bettorYes1,
            payout: expectedPayout + initialBet
        });

        bettorBalBefore = usdb.balanceOf(bettorYes1);
        protocolBalBefore = usdb.balanceOf(address(wdyt));

        assertEq(wdyt.redeem(id, bettorYes1), expectedPayout, "INCORRECT_PAYOUT"); 

        assertEq(usdb.balanceOf(bettorYes1) - bettorBalBefore, expectedPayout + initialBet, "WRONG BALANCE: BETTOR");
        assertEq(protocolBalBefore - usdb.balanceOf(address(wdyt)), expectedPayout + initialBet, "WRONG BALANCE: PROTOCOL");

        totalAssets -= expectedPayout;
        data.totalYesShares -= shares1;

        console.log('first $25 bet');
        console.log(expectedPayout);

        expectedPayout = (shares2 * totalAssets) / data.totalYesShares;
        initialBet = wdyt.getBet(id, bettorYes2).yesBets;

        assertEq(wdyt.redeem(id, bettorYes2), expectedPayout, "INCORRECT_PAYOUT");

        console.log('second $25 bet');
        console.log(expectedPayout);
    }
}