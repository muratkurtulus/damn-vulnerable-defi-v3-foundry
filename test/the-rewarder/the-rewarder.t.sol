// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import "../../src/the-rewarder/AccountingToken.sol";
import {FlashLoanerPool} from "../../src/the-rewarder/FlashLoanerPool.sol";
import "../../src/the-rewarder/RewardToken.sol";
import "../../src/the-rewarder/TheRewarderPool.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract TheRewarderPoolTest is Test {
    address public deployer;
    address public player;
    address public alice;
    address public bob;
    address public charlie;
    address public david;

    AccountingToken public accountingToken;
    FlashLoanerPool public flashLoanPool;
    RewardToken public rewardToken;
    TheRewarderPool public rewarderPool;
    DamnValuableToken public liquidityToken;
    address[4] public users;

    uint256 public constant TOKENS_IN_LENDER_POOL = 1_000_000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");
        users = [alice, bob, charlie, david];

        vm.startPrank(deployer);

        liquidityToken = new DamnValuableToken();
        flashLoanPool = new FlashLoanerPool(address(liquidityToken));

        liquidityToken.transfer(address(flashLoanPool), TOKENS_IN_LENDER_POOL);

        rewarderPool = new TheRewarderPool(address(liquidityToken));
        rewardToken = rewarderPool.rewardToken();
        accountingToken = rewarderPool.accountingToken();

        // Check roles in accounting token
        assertEq(accountingToken.owner(), address(rewarderPool));
        uint256 minterRole = accountingToken.MINTER_ROLE();
        uint256 snapshotRole = accountingToken.SNAPSHOT_ROLE();
        uint256 burnerRole = accountingToken.BURNER_ROLE();
        assertEq(accountingToken.hasAllRoles(address(rewarderPool), minterRole | snapshotRole | burnerRole), true);
        vm.stopPrank();

        uint256 depositAmount = 100 ether;
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(deployer);
            liquidityToken.transfer(users[i], depositAmount);

            vm.startPrank(users[i]);
            liquidityToken.approve(address(rewarderPool), depositAmount);
            rewarderPool.deposit(depositAmount);
            vm.stopPrank();

            assertEq(accountingToken.balanceOf(users[i]), depositAmount);
        }

        assertEq(accountingToken.totalSupply(), depositAmount * users.length);
        assertEq(rewardToken.totalSupply(), 0);
        skip(5 days);

        uint256 rewardsInRound = rewarderPool.REWARDS();
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            rewarderPool.distributeRewards();
            assertEq(rewardToken.balanceOf(users[i]), rewardsInRound / users.length);
        }
        assertEq(rewardToken.totalSupply(), rewardsInRound);
        assertEq(liquidityToken.balanceOf(player), 0);
        assertEq(rewarderPool.roundNumber(), 2);
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertEq(rewarderPool.roundNumber(), 3);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            rewarderPool.distributeRewards();
            uint256 userRewards = rewardToken.balanceOf(users[i]);
            uint256 delta = userRewards - (rewarderPool.REWARDS() / users.length);
            assertLt(delta, 10e16);
        }
    }
}
