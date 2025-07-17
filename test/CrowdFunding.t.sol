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
        assertEq(crowdFunding.platformFeePercentage(), 300); // 3%
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
        uint256 platformFee = (totalAmount * 300) / 10000; // 3%
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
        uint256 platformFee = (totalAmount * 300) / 10000; // 3%
        uint256 netAmount = totalAmount - platformFee;
        
        // Check balances
        assertEq(mockToken.balanceOf(beneficiary), initialBeneficiaryBalance + netAmount);
        assertEq(mockToken.balanceOf(platformAddress), initialPlatformBalance + platformFee);
        
        // Check campaign current amount is reset
        (,,,,,,uint256 currentAmount,,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(currentAmount, 0);
    }
    
    function test_WithdrawFundsByAnyone() public {
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
        
        // Withdraw funds using a different address (not beneficiary)
        vm.prank(contributor1); // Using contributor1 instead of beneficiary
        crowdFunding.withdrawFunds(campaignId);
        
        // Calculate expected amounts
        uint256 totalAmount = 1 ether;
        uint256 platformFee = (totalAmount * 300) / 10000; // 3%
        uint256 netAmount = totalAmount - platformFee;
        
        // Check balances - funds should still go to beneficiary
        assertEq(beneficiary.balance, initialBeneficiaryBalance + netAmount);
        assertEq(platformAddress.balance, initialPlatformBalance + platformFee);
        
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
        
        uint256 expectedPlatformFee = (totalAmount * 300) / 10000; // 3%
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
    
    function test_RevertContributeAfterGoalReached() public {
        // Create campaign
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Test Campaign",
            "Test Description",
            beneficiary,
            1 ether,
            30,
            address(0)
        );
        
        // Contribute exactly the funding goal
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 1 ether}(campaignId);
        
        // Verify campaign is successful
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
        
        // Try to contribute again - should revert
        vm.deal(contributor2, 0.5 ether);
        vm.prank(contributor2);
        vm.expectRevert(CrowdFunding.CampaignNotActive.selector);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
    }
    
    function test_RevertContributeERC20AfterGoalReached() public {
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
        
        // Contribute exactly the funding goal
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 100 * 10**18);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(campaignId, 100 * 10**18);
        
        // Verify campaign is successful
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
        
        // Try to contribute again - should revert
        vm.prank(contributor2);
        mockToken.approve(address(crowdFunding), 50 * 10**18);
        
        vm.prank(contributor2);
        vm.expectRevert(CrowdFunding.CampaignNotActive.selector);
        crowdFunding.contributeERC20(campaignId, 50 * 10**18);
    }
    
    // ============= 数值边界测试 =============
    
    /// @notice 测试最小金额边界
    function test_MinimumAmountBoundary() public {
        // 创建活动
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Minimum Amount Test",
            "Test Description",
            beneficiary,
            1 wei, // 最小目标金额
            30,
            address(0)
        );
        
        // 测试最小捐款金额 1 wei
        vm.deal(contributor1, 1 wei);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 1 wei}(campaignId);
        
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 1 wei);
        
        // 验证活动成功
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
    }
    
    /// @notice 测试最大金额边界（接近uint256最大值）
    function test_MaximumAmountBoundary() public {
        uint256 maxAmount = type(uint256).max / 2; // 防止溢出
        
        // 创建大额目标活动
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Maximum Amount Test",
            "Test Description",
            beneficiary,
            maxAmount,
            30,
            address(0)
        );
        
        // 设置大额余额并捐款
        vm.deal(contributor1, maxAmount);
        vm.prank(contributor1);
        crowdFunding.contribute{value: maxAmount}(campaignId);
        
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), maxAmount);
        
        // 验证活动成功
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
    }
    
    /// @notice 测试手续费计算的数值边界
    function test_PlatformFeeCalculationBoundary() public {
        // 测试1 wei的手续费计算
        (uint256 platformFee1, uint256 netAmount1) = crowdFunding.calculateAmounts(1 wei);
        assertEq(platformFee1, 0); // 1 wei * 300 / 10000 = 0 (整数除法)
        assertEq(netAmount1, 1 wei);
        
        // 测试33 wei的手续费计算（还不能产生非零手续费）
        (uint256 platformFee33, uint256 netAmount33) = crowdFunding.calculateAmounts(33 wei);
        assertEq(platformFee33, 0); // 33 * 300 / 10000 = 0 (整数除法)
        assertEq(netAmount33, 33 wei);
        
        // 测试34 wei的手续费计算（第一个产生非零手续费的值）
        (uint256 platformFee34, uint256 netAmount34) = crowdFunding.calculateAmounts(34 wei);
        assertEq(platformFee34, 1); // 34 * 300 / 10000 = 1 (整数除法)
        assertEq(netAmount34, 33 wei);
        
        // 测试使3%手续费生效的最小金额
        uint256 minForFee = 34; // 需要至少34 wei才能产生1 wei的手续费 (34 * 300 / 10000 = 1)
        (uint256 platformFeeMin, uint256 netAmountMin) = crowdFunding.calculateAmounts(minForFee);
        assertEq(platformFeeMin, 1); // 刚好1 wei手续费
        assertEq(netAmountMin, minForFee - 1);
    }
    
    /// @notice 测试手续费百分比边界值
    function test_PlatformFeePercentageBoundary() public {
        // 测试设置0%手续费
        vm.prank(owner);
        crowdFunding.updatePlatformFeePercentage(0);
        assertEq(crowdFunding.platformFeePercentage(), 0);
        
        (uint256 platformFee, uint256 netAmount) = crowdFunding.calculateAmounts(1 ether);
        assertEq(platformFee, 0);
        assertEq(netAmount, 1 ether);
        
        // 测试设置100%手续费
        vm.prank(owner);
        crowdFunding.updatePlatformFeePercentage(10000); // 100%
        assertEq(crowdFunding.platformFeePercentage(), 10000);
        
        (uint256 platformFee100, uint256 netAmount100) = crowdFunding.calculateAmounts(1 ether);
        assertEq(platformFee100, 1 ether);
        assertEq(netAmount100, 0);
        
        // 测试超过100%应该失败
        vm.prank(owner);
        vm.expectRevert(CrowdFunding.InvalidFeePercentage.selector);
        crowdFunding.updatePlatformFeePercentage(10001);
        
        // 恢复到3%
        vm.prank(owner);
        crowdFunding.updatePlatformFeePercentage(300);
    }
    
    /// @notice 测试时间边界
    function test_TimeBoundary() public {
        // 创建1天的活动
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Time Boundary Test",
            "Test Description",
            beneficiary,
            1 ether,
            1, // 1天
            address(0)
        );
        
        uint256 deadline = block.timestamp + 1 days;
        
        // 在截止前1秒捐款应该成功
        vm.warp(deadline - 1);
        vm.deal(contributor1, 0.5 ether);
        vm.prank(contributor1);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
        
        // 在截止时间捐款应该失败
        vm.warp(deadline);
        vm.deal(contributor2, 0.5 ether);
        vm.prank(contributor2);
        vm.expectRevert(CrowdFunding.CampaignDeadlinePassed.selector);
        crowdFunding.contribute{value: 0.5 ether}(campaignId);
        
        // 检查活动状态
        crowdFunding.checkCampaignStatus(campaignId);
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Failed));
    }
    
    /// @notice 测试多次小额捐款累积
    function test_AccumulativeSmallContributions() public {
        // 创建活动
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "Accumulative Test",
            "Test Description",
            beneficiary,
            1000 wei,
            30,
            address(0)
        );
        
        // 进行1000次1 wei的捐款
        vm.deal(contributor1, 1000 wei);
        for (uint i = 1; i <= 1000; i++) {
            vm.prank(contributor1);
            crowdFunding.contribute{value: 1 wei}(campaignId);
        }
        
        // 验证总捐款金额
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 1000 wei);
        
        // 验证活动成功
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
    }
    
    /// @notice 测试ERC20代币的精度边界
    function test_ERC20PrecisionBoundary() public {
        // 创建ERC20活动，目标为1个最小单位
        vm.prank(owner);
        uint256 campaignId = crowdFunding.createCampaign(
            "ERC20 Precision Test",
            "Test Description",
            beneficiary,
            1, // 1个最小单位
            30,
            address(mockToken)
        );
        
        // 捐款1个最小单位
        vm.prank(contributor1);
        mockToken.approve(address(crowdFunding), 1);
        
        vm.prank(contributor1);
        crowdFunding.contributeERC20(campaignId, 1);
        
        assertEq(crowdFunding.getUserContribution(campaignId, contributor1), 1);
        
        // 验证活动成功
        (,,,,,,,CrowdFunding.CampaignStatus status,) = crowdFunding.getCampaignDetails(campaignId);
        assertEq(uint256(status), uint256(CrowdFunding.CampaignStatus.Successful));
    }
    
    /// @notice 测试手续费计算不会导致整数溢出
    function test_FeeCalculationOverflowProtection() public {
        // 测试接近最大值的金额，确保不会溢出
        // 最大安全值应该是 type(uint256).max / 300，这样乘以300不会溢出
        uint256 maxSafeAmount = type(uint256).max / 300;
        
        (uint256 platformFee, uint256 netAmount) = crowdFunding.calculateAmounts(maxSafeAmount);
        
        // 验证计算正确且无溢出
        uint256 expectedFee = (maxSafeAmount * 300) / 10000;
        assertEq(platformFee, expectedFee);
        assertEq(netAmount, maxSafeAmount - expectedFee);
        assertEq(platformFee + netAmount, maxSafeAmount);
    }
}
