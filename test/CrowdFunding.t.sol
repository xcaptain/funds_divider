// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CrowdFunding} from "../src/CrowdFunding.sol";

contract CrowdFundingTest is Test {
    CrowdFunding public crowdFunding;
    address public owner = address(1);
    address public platformAddress = address(2);
    address public beneficiary = address(3);
    address public contributor1 = address(4);
    address public contributor2 = address(5);
    
    event ProjectCreated(
        uint256 indexed projectId,
        string title,
        address indexed beneficiary,
        uint256 fundingGoal,
        uint256 deadline
    );
    
    event ContributionMade(
        uint256 indexed projectId,
        address indexed contributor,
        uint256 amount
    );
    
    event ProjectSuccessful(
        uint256 indexed projectId,
        uint256 totalAmount
    );
    
    event FundsWithdrawn(
        uint256 indexed projectId,
        address indexed beneficiary,
        uint256 netAmount,
        uint256 platformFee
    );
    
    function setUp() public {
        crowdFunding = new CrowdFunding(owner, platformAddress);
    }
    
    function test_Constructor() public {
        assertEq(crowdFunding.owner(), owner);
        assertEq(crowdFunding.platformAddress(), platformAddress);
        assertEq(crowdFunding.platformFeePercentage(), 250); // 2.5%
        assertEq(crowdFunding.projectCount(), 0);
    }
    
    function test_CreateProject() public {
        vm.prank(beneficiary);
        
        vm.expectEmit(true, true, false, true);
        emit ProjectCreated(1, "Test Project", beneficiary, 1 ether, block.timestamp + 30 days);
        
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        assertEq(projectId, 1);
        assertEq(crowdFunding.projectCount(), 1);
        
        (
            uint256 id,
            string memory title,
            string memory description,
            address projectBeneficiary,
            uint256 fundingGoal,
            uint256 deadline,
            uint256 currentAmount,
            CrowdFunding.ProjectStatus status,
            uint256 contributorsCount
        ) = crowdFunding.getProjectDetails(1);
        
        assertEq(id, 1);
        assertEq(title, "Test Project");
        assertEq(description, "Test Description");
        assertEq(projectBeneficiary, beneficiary);
        assertEq(fundingGoal, 1 ether);
        assertEq(deadline, block.timestamp + 30 days);
        assertEq(currentAmount, 0);
        assertEq(uint256(status), uint256(CrowdFunding.ProjectStatus.Active));
        assertEq(contributorsCount, 0);
    }
    
    function test_Contribute() public {
        // Create project first
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        // Contribute to project
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        
        vm.expectEmit(true, true, false, true);
        emit ContributionMade(projectId, contributor1, 0.5 ether);
        
        crowdFunding.contribute{value: 0.5 ether}(projectId);
        
        // Check contribution
        assertEq(crowdFunding.getUserContribution(projectId, contributor1), 0.5 ether);
        
        // Check project details
        (,,,,,,uint256 currentAmount,,uint256 contributorsCount) = crowdFunding.getProjectDetails(projectId);
        assertEq(currentAmount, 0.5 ether);
        assertEq(contributorsCount, 1);
    }
    
    function test_ProjectSuccess() public {
        // Create project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        // Contribute enough to reach goal
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        
        vm.expectEmit(true, true, false, true);
        emit ProjectSuccessful(projectId, 1 ether);
        
        crowdFunding.contribute{value: 1 ether}(projectId);
        
        // Check project status
        (,,,,,,,CrowdFunding.ProjectStatus status,) = crowdFunding.getProjectDetails(projectId);
        assertEq(uint256(status), uint256(CrowdFunding.ProjectStatus.Successful));
    }
    
    function test_WithdrawFunds() public {
        // Create project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        // Contribute to make it successful
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 1 ether}(projectId);
        
        // Check initial balances
        uint256 initialBeneficiaryBalance = beneficiary.balance;
        uint256 initialPlatformBalance = platformAddress.balance;
        
        // Withdraw funds
        vm.prank(beneficiary);
        
        // Calculate expected amounts
        uint256 totalAmount = 1 ether;
        uint256 platformFee = (totalAmount * 250) / 10000; // 2.5%
        uint256 netAmount = totalAmount - platformFee;
        
        vm.expectEmit(true, true, false, true);
        emit FundsWithdrawn(projectId, beneficiary, netAmount, platformFee);
        
        crowdFunding.withdrawFunds(projectId);
        
        // Check balances
        assertEq(beneficiary.balance, initialBeneficiaryBalance + netAmount);
        assertEq(platformAddress.balance, initialPlatformBalance + platformFee);
        
        // Check project current amount is reset
        (,,,,,,uint256 currentAmount,,) = crowdFunding.getProjectDetails(projectId);
        assertEq(currentAmount, 0);
    }
    
    function test_ProjectFailure() public {
        // Create project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        // Contribute less than goal
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(projectId);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check project status
        crowdFunding.checkProjectStatus(projectId);
        
        (,,,,,,,CrowdFunding.ProjectStatus status,) = crowdFunding.getProjectDetails(projectId);
        assertEq(uint256(status), uint256(CrowdFunding.ProjectStatus.Failed));
    }
    
    function test_RequestRefund() public {
        // Create project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30
        );
        
        // Contribute
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(projectId);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check project status to make it failed
        crowdFunding.checkProjectStatus(projectId);
        
        // Request refund
        uint256 initialBalance = contributor1.balance;
        vm.prank(contributor1);
        crowdFunding.requestRefund(projectId);
        
        // Check refund
        assertEq(contributor1.balance, initialBalance + 0.5 ether);
        assertEq(crowdFunding.getUserContribution(projectId, contributor1), 0);
    }
    
    function test_UpdatePlatformAddress() public {
        address newPlatformAddress = address(99);
        
        vm.prank(owner);
        crowdFunding.updatePlatformAddress(newPlatformAddress);
        
        assertEq(crowdFunding.platformAddress(), newPlatformAddress);
    }
    
    function test_UpdatePlatformFeePercentage() public {
        uint256 newFeePercentage = 500; // 5%
        
        vm.prank(owner);
        crowdFunding.updatePlatformFeePercentage(newFeePercentage);
        
        assertEq(crowdFunding.platformFeePercentage(), newFeePercentage);
    }
    
    function test_CalculateAmounts() public {
        uint256 totalAmount = 1 ether;
        (uint256 platformFee, uint256 netAmount) = crowdFunding.calculateAmounts(totalAmount);
        
        uint256 expectedPlatformFee = (totalAmount * 250) / 10000; // 2.5%
        uint256 expectedNetAmount = totalAmount - expectedPlatformFee;
        
        assertEq(platformFee, expectedPlatformFee);
        assertEq(netAmount, expectedNetAmount);
    }
    
    function test_RevertInvalidAddress() public {
        vm.expectRevert(CrowdFunding.InvalidAddress.selector);
        new CrowdFunding(owner, address(0));
    }
    
    function test_RevertInvalidFundingGoal() public {
        vm.prank(beneficiary);
        vm.expectRevert(CrowdFunding.InvalidAmount.selector);
        crowdFunding.createProject("Test", "Test", 0, 30);
    }
    
    function test_RevertInvalidDuration() public {
        vm.prank(beneficiary);
        vm.expectRevert(CrowdFunding.InvalidDuration.selector);
        crowdFunding.createProject("Test", "Test", 1 ether, 0);
    }
    
    function test_RevertContributeToNonExistentProject() public {
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.ProjectNotFound.selector);
        crowdFunding.contribute{value: 1 ether}(999);
    }
    
    function test_RevertContributeZeroAmount() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject("Test", "Test", 1 ether, 30);
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidAmount.selector);
        crowdFunding.contribute{value: 0}(projectId);
    }
}
