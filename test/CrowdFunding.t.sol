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

contract CrowdFundingTest is Test {
    CrowdFunding public crowdFunding;
    MockERC20 public mockToken;
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
        uint256 deadline,
        address indexed tokenAddress
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
        mockToken = new MockERC20(1000000 * 10**18); // 1M tokens
        
        // Give some tokens to contributors
        mockToken.mint(contributor1, 100 * 10**18);
        mockToken.mint(contributor2, 100 * 10**18);
    }
    
    function test_Constructor() public {
        assertEq(crowdFunding.owner(), owner);
        assertEq(crowdFunding.platformAddress(), platformAddress);
        assertEq(crowdFunding.platformFeePercentage(), 250); // 2.5%
        assertEq(crowdFunding.projectCount(), 0);
    }
    
    function test_CreateProject() public {
        vm.prank(beneficiary);
        
        vm.expectEmit(true, true, true, true);
        emit ProjectCreated(1, "Test Project", beneficiary, 1 ether, block.timestamp + 30 days, address(0));
        
        uint256 projectId = crowdFunding.createProject(
            "Test Project",
            "Test Description",
            1 ether,
            30,
            address(0) // Native token
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
            30,
            address(0) // Native token
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
            30,
            address(0) // Native token
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
    
    function test_ContributeERC20() public {
        // Create ERC20 project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18, // 100 tokens
            30,
            address(mockToken)
        );
        
        // Approve and contribute
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        vm.expectEmit(true, true, false, true);
        emit ContributionMade(projectId, contributor1, 50 * 10**18);
        
        crowdFunding.contributeERC20(projectId, 50 * 10**18);
        
        // Check contribution
        assertEq(crowdFunding.getUserContribution(projectId, contributor1), 50 * 10**18);
        
        // Check project details
        (,,,,,,uint256 currentAmount,,uint256 contributorsCount) = crowdFunding.getProjectDetails(projectId);
        assertEq(currentAmount, 50 * 10**18);
        assertEq(contributorsCount, 1);
    }
    
    function test_ERC20ProjectSuccess() public {
        // Create ERC20 project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18, // 100 tokens
            30,
            address(mockToken)
        );
        
        // Contribute enough to reach goal
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 100 * 10**18);
        
        vm.prank(contributor1);
        vm.expectEmit(true, true, false, true);
        emit ProjectSuccessful(projectId, 100 * 10**18);
        
        crowdFunding.contributeERC20(projectId, 100 * 10**18);
        
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
            30,
            address(0) // Native token
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
    
    function test_WithdrawFundsERC20() public {
        // Create ERC20 project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        // Contribute to make it successful
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 100 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(projectId, 100 * 10**18);
        
        // Check initial balances
        uint256 initialBeneficiaryBalance = mockToken.balanceOf(beneficiary);
        uint256 initialPlatformBalance = mockToken.balanceOf(platformAddress);
        
        // Withdraw funds
        vm.prank(beneficiary);
        
        // Calculate expected amounts
        uint256 totalAmount = 100 * 10**18;
        uint256 platformFee = (totalAmount * 250) / 10000; // 2.5%
        uint256 netAmount = totalAmount - platformFee;
        
        vm.expectEmit(true, true, false, true);
        emit FundsWithdrawn(projectId, beneficiary, netAmount, platformFee);
        
        crowdFunding.withdrawFunds(projectId);
        
        // Check balances
        assertEq(mockToken.balanceOf(beneficiary), initialBeneficiaryBalance + netAmount);
        assertEq(mockToken.balanceOf(platformAddress), initialPlatformBalance + platformFee);
        
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
            30,
            address(0) // Native token
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
            30,
            address(0) // Native token
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
    
    function test_RequestRefundERC20() public {
        // Create ERC20 project
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        // Contribute
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(projectId, 50 * 10**18);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        // Check project status to make it failed
        crowdFunding.checkProjectStatus(projectId);
        
        // Request refund
        uint256 initialBalance = mockToken.balanceOf(contributor1);
        vm.prank(contributor1);
        crowdFunding.requestRefund(projectId);
        
        // Check refund
        assertEq(mockToken.balanceOf(contributor1), initialBalance + 50 * 10**18);
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
        crowdFunding.createProject("Test", "Test", 0, 30, address(0));
    }
    
    function test_RevertInvalidDuration() public {
        vm.prank(beneficiary);
        vm.expectRevert(CrowdFunding.InvalidDuration.selector);
        crowdFunding.createProject("Test", "Test", 1 ether, 0, address(0));
    }
    
    function test_RevertContributeToNonExistentProject() public {
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.ProjectNotFound.selector);
        crowdFunding.contribute{value: 1 ether}(999);
    }
    
    function test_RevertContributeZeroAmount() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject("Test", "Test", 1 ether, 30, address(0));
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidAmount.selector);
        crowdFunding.contribute{value: 0}(projectId);
    }
    
    function test_RevertContributeNativeToERC20Project() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidTokenAddress.selector);
        crowdFunding.contribute{value: 1 ether}(projectId);
    }
    
    function test_RevertContributeERC20ToNativeProject() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test Native Project",
            "Test Description", 
            1 ether,
            30,
            address(0)
        );
        
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InvalidTokenAddress.selector);
        crowdFunding.contributeERC20(projectId, 50 * 10**18);
    }
    
    function test_RevertInsufficientERC20Balance() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            1000 * 10**18,
            30,
            address(mockToken)
        );
        
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 1000 * 10**18);
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InsufficientBalance.selector);
        crowdFunding.contributeERC20(projectId, 1000 * 10**18); // More than balance
    }
    
    function test_RevertInsufficientERC20Allowance() public {
        vm.prank(beneficiary);
        uint256 projectId = crowdFunding.createProject(
            "Test ERC20 Project",
            "Test Description",
            100 * 10**18,
            30,
            address(mockToken)
        );
        
        // Don't approve enough
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 10 * 10**18);
        
        vm.prank(contributor1);
        vm.expectRevert(CrowdFunding.InsufficientAllowance.selector);
        crowdFunding.contributeERC20(projectId, 50 * 10**18); // More than allowance
    }
}
