// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CrowdFunding} from "../src/CrowdFunding.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    
    constructor(uint256 _initialSupply) {
        _totalSupply = _initialSupply;
        _balances[msg.sender] = _initialSupply;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract CrowdFundingNewTest is Test {
    CrowdFunding public crowdFunding;
    MockERC20 public mockToken;
    address public owner = address(1);
    address public platformAddress = address(2);
    address public beneficiary = address(3);
    address public contributor1 = address(4);
    address public contributor2 = address(5);
    
    function setUp() public {
        crowdFunding = new CrowdFunding(owner, platformAddress);
        mockToken = new MockERC20(1000000 * 10**18); // 1M tokens
        
        // Give some tokens to contributors
        mockToken.mint(contributor1, 100 * 10**18);
        mockToken.mint(contributor2, 100 * 10**18);
    }
    
    function test_Constructor() public {
        assertEq(crowdFunding.owner(), owner);
        assertEq(crowdFunding.platformAddress(), platformAddress);
        assertEq(crowdFunding.platformFeePercentage(), 250); // 2.5%
        assertEq(crowdFunding.campaignCount(), 0);
    }
    
    function test_CreateCampaign() public {
        vm.prank(owner);
        
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        assertEq(campaignId, 1);
        assertEq(crowdFunding.campaignCount(), 1);
        
        (
            uint256 id,
            string memory title,
            string memory description,
            address campaignBeneficiary,
            uint256 fundingGoal,
            uint256 deadline,
            uint256 currentAmount,
            CrowdFunding.CampaignStatus status,
            uint256 contributorsCount
        ) = crowdFunding.getCampaignDetails(1);
        
        assertEq(id, 1);
        assertEq(title, "Test Campaign");
        assertEq(description, "Test Description");
        assertEq(campaignBeneficiary, beneficiary);
        assertEq(fundingGoal, 1 ether);
        assertEq(deadline, block.timestamp + 30 days);
        assertEq(currentAmount, 0);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Active));
        assertEq(contributorsCount, 0);
    }
    
    function test_ContributeNative() public {
        // Create campaign first
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        // Contribute to campaign
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
        
        // Check contribution
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 0.5 ether);
        
        // Check campaign details
        (,,,,,,uint256 currentAmount,,uint256 contributorsCount) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(currentAmount, 0.5 ether);
        assertEq(contributorsCount, 1);
    }
    
    function test_ContributeERC20() public {
        // Create ERC20 campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test ERC20 Campaign",
            "Test Description",
            beneficiary,
            100 * 10**18, // 100 tokens
            30,
            address(mockToken)
        );
        
        // Approve and contribute
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(campaignId, 50 * 10**18);
        
        // Check contribution
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 50 * 10**18);
        
        // Check campaign details
        (,,,,,,uint256 currentAmount,,uint256 contributorsCount) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(currentAmount, 50 * 10**18);
        assertEq(contributorsCount, 1);
    }
    
    function test_CampaignSuccess() public {
        // Create campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        // Contribute enough to reach goal
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 1 ether}(campaignId);
        
        // Check campaign status
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
    }
    
    function test_WithdrawFundsNative() public {
        // Create campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        // Contribute to make it successful
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 1 ether}(campaignId);
        
        // Check initial balances
        uint256 initialBeneficiaryBalance = beneficiary.balance;
        uint256 initialPlatformBalance = platformAddress.balance;
        
        // Withdraw funds
        vm.prank(beneficiary);
        crowdFunding.withdrawFunds(campaignId);
        
        // Calculate expected amounts
        uint256 totalAmount = 1 ether;
        uint256 platformFee = (totalAmount * 250) / 10000; // 2.5%
        uint256 netAmount = totalAmount - platformFee;
        
        // Check balances
        assertEq(beneficiary.balance, initialBeneficiaryBalance + netAmount);
        assertEq(platformAddress.balance, initialPlatformBalance + platformFee);
        
        // Check campaign current amount is reset
        (,,,,,,uint256 currentAmount,,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(currentAmount, 0);
    }
    
    function test_WithdrawFundsERC20() public {
        // Create ERC20 campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test ERC20 Campaign",
            "Test Description",
            beneficiary,
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        // Contribute to make it successful
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 100 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(campaignId, 100 * 10**18);
        
        // Check initial balances
        uint256 initialBeneficiaryBalance = mockToken.balanceOf(beneficiary);
        uint256 initialPlatformBalance = mockToken.balanceOf(platformAddress);
        
        // Withdraw funds
        vm.prank(beneficiary);
        crowdFunding.withdrawFunds(campaignId);
        
        // Calculate expected amounts
        uint256 totalAmount = 100 * 10**18;
        uint256 platformFee = (totalAmount * 250) / 10000; // 2.5%
        uint256 netAmount = totalAmount - platformFee;
        
        // Check balances
        assertEq(mockToken.balanceOf(beneficiary), initialBeneficiaryBalance + netAmount);
        assertEq(mockToken.balanceOf(platformAddress), initialPlatformBalance + platformFee);
        
        // Check campaign current amount is reset
        (,,,,,,uint256 currentAmount,,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(currentAmount, 0);
    }
    
    function test_CampaignFailure() public {
        // Create campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        // Contribute less than goal
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check campaign status
        crowdFunding.checkCampaignStatus(campaignId);
        
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Failed));
    }
    
    function test_RequestRefundNative() public {
        // Create campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0) // Native token
        );
        
        // Contribute
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check campaign status to make it failed
        crowdFunding.checkCampaignStatus(campaignId);
        
        // Request refund
        uint256 initialBalance = contributor1.balance;
        vm.prank(contributor1);
        crowdFunding.requestRefund(campaignId);
        
        // Check refund
        assertEq(contributor1.balance, initialBalance + 0.5 ether);
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 0);
    }
    
    function test_RequestRefundERC20() public {
        // Create ERC20 campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test ERC20 Campaign",
            "Test Description",
            beneficiary,
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        // Contribute
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(campaignId, 50 * 10**18);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check campaign status to make it failed
        crowdFunding.checkCampaignStatus(campaignId);
        
        // Request refund
        uint256 initialBalance = mockToken.balanceOf(contributor1);
        vm.prank(contributor1);
        crowdFunding.requestRefund(campaignId);
        
        // Check refund
        assertEq(mockToken.balanceOf(contributor1), initialBalance + 50 * 10**18);
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 0);
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
        vm.prank(owner);
        vm.expectRevert(CrowdFunding.InvalidAmount.selector);
        crowdFunding.createCampaign("Test", "Test", beneficiary, 0, 30, address(0));
    }
    
    function test_RevertInvalidDuration() public {
        vm.prank(owner);
        vm.expectRevert(CrowdFunding.InvalidDuration.selector);
        crowdFunding.createCampaign("Test", "Test", beneficiary, 1 ether, 0, address(0));
    }
    
    function test_RevertNonOwnerCreateCampaign() public {
        vm.prank(beneficiary);
        vm.expectRevert();
        crowdFunding.createCampaign("Test", "Test", beneficiary, 1 ether, 30, address(0));
    }
    
    function test_RevertContributeToNonExistentCampaign() public {
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.CampaignNotFound.selector);
        crowdFunding.contribute{value: 1 ether}(999);
    }
    
    function test_RevertContributeZeroAmount() public {
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign("Test", "Test", beneficiary, 1 ether, 30, address(0));
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidAmount.selector);
        crowdFunding.contribute{value: 0}(campaignId);
    }
    
    function test_RevertContributeNativeToERC20Campaign() public {
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test ERC20 Campaign",
            "Test Description",
            beneficiary,
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidTokenAddress.selector);
        crowdFunding.contribute{value: 1 ether}(campaignId);
    }
    
    function test_RevertContributeERC20ToNativeCampaign() public {
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Native Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0)
        );
        
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidTokenAddress.selector);
        crowdFunding.contributeERC20(campaignId, 50 * 10**18);
    }
}
