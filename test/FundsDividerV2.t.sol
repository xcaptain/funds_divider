// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/FundsDividerV2.sol";

/// @title Mock ERC20 代币合约
/// @notice 用于测试的简单 ERC20 实现
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @title FundsDividerV2 测试合约
contract FundsDividerV2Test is Test {
    FundsDividerV2 public fundsDivider;
    MockERC20 public mockToken;
    
    address public admin = address(0x1);
    address public feeAddress = address(0x2);
    address public user = address(0x3);
    address public destAddress = address(0x4);
    address public beneficiary1 = address(0x5);
    address public beneficiary2 = address(0x6);
    address public beneficiary3 = address(0x7);
    
    uint256 public constant PERCENTAGE_BASE = 10000;
    uint256 public constant DEFAULT_FEE_PERCENTAGE = 300; // 3%
    
    /// @notice 设置测试环境
    function setUp() public {
        // 部署合约
        fundsDivider = new FundsDividerV2(admin, feeAddress);
        mockToken = new MockERC20();
        
        // 为测试地址分配 ETH
        vm.deal(user, 100 ether);
        vm.deal(destAddress, 1 ether);
        vm.deal(beneficiary1, 1 ether);
        vm.deal(beneficiary2, 1 ether);
        vm.deal(beneficiary3, 1 ether);
        
        // 为测试地址分配代币
        mockToken.mint(user, 1000000 * 10**18);
        
        // 用户授权合约使用代币
        vm.prank(user);
        mockToken.approve(address(fundsDivider), type(uint256).max);
    }
    
    /// @notice 测试合约初始化
    function testInitialization() public {
        assertEq(fundsDivider.admin(), admin);
        assertEq(fundsDivider.feeAddress(), feeAddress);
        assertEq(fundsDivider.DEFAULT_FEE_PERCENTAGE(), DEFAULT_FEE_PERCENTAGE);
        assertEq(fundsDivider.PERCENTAGE_BASE(), PERCENTAGE_BASE);
    }
    
    /// @notice 测试管理员权限
    function testAdminFunctions() public {
        address newAdmin = address(0x8);
        address newFeeAddress = address(0x9);
        
        // 只有管理员可以更新管理员
        vm.prank(admin);
        fundsDivider.updateAdmin(newAdmin);
        assertEq(fundsDivider.admin(), newAdmin);
        
        // 非管理员无法更新管理员
        vm.prank(user);
        vm.expectRevert(FundsDividerV2.Unauthorized.selector);
        fundsDivider.updateAdmin(user);
        
        // 新管理员可以更新手续费地址
        vm.prank(newAdmin);
        fundsDivider.updateFeeAddress(newFeeAddress);
        assertEq(fundsDivider.feeAddress(), newFeeAddress);
    }
    
    /// @notice 测试受益人列表设置
    function testSetBeneficiaryList() public {
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](2);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 2000 // 20%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 1000 // 10%
        });
        
        // 管理员可以设置受益人列表
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        // 验证受益人列表设置成功
        assertTrue(fundsDivider.hasBeneficiaryList(destAddress));
        
        FundsDividerV2.Beneficiary[] memory storedBeneficiaries = fundsDivider.getBeneficiaryList(destAddress);
        assertEq(storedBeneficiaries.length, 2);
        assertEq(storedBeneficiaries[0].beneficiary, beneficiary1);
        assertEq(storedBeneficiaries[0].percentage, 2000);
        assertEq(storedBeneficiaries[1].beneficiary, beneficiary2);
        assertEq(storedBeneficiaries[1].percentage, 1000);
    }
    
    /// @notice 测试受益人列表验证
    function testBeneficiaryListValidation() public {
        // 测试空列表
        FundsDividerV2.Beneficiary[] memory emptyBeneficiaries = new FundsDividerV2.Beneficiary[](0);
        vm.prank(admin);
        vm.expectRevert(FundsDividerV2.EmptyBeneficiaryList.selector);
        fundsDivider.setBeneficiaryList(destAddress, emptyBeneficiaries);
        
        // 测试百分比总和超过 100%
        FundsDividerV2.Beneficiary[] memory invalidBeneficiaries = new FundsDividerV2.Beneficiary[](2);
        invalidBeneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 6000 // 60%
        });
        invalidBeneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 5000 // 50%
        });
        
        vm.prank(admin);
        vm.expectRevert(FundsDividerV2.InvalidPercentageSum.selector);
        fundsDivider.setBeneficiaryList(destAddress, invalidBeneficiaries);
        
        // 测试无效受益人地址
        FundsDividerV2.Beneficiary[] memory zeroAddressBeneficiaries = new FundsDividerV2.Beneficiary[](1);
        zeroAddressBeneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: address(0),
            percentage: 1000
        });
        
        vm.prank(admin);
        vm.expectRevert(FundsDividerV2.InvalidAddress.selector);
        fundsDivider.setBeneficiaryList(destAddress, zeroAddressBeneficiaries);
    }
    
    /// @notice 测试移除受益人列表
    function testRemoveBeneficiaryList() public {
        // 先设置受益人列表
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](1);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 2000
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        assertTrue(fundsDivider.hasBeneficiaryList(destAddress));
        
        // 移除受益人列表
        vm.prank(admin);
        fundsDivider.removeBeneficiaryList(destAddress);
        assertTrue(!fundsDivider.hasBeneficiaryList(destAddress));
        
        // 验证列表已清空
        FundsDividerV2.Beneficiary[] memory emptyList = fundsDivider.getBeneficiaryList(destAddress);
        assertEq(emptyList.length, 0);
    }
    
    /// @notice 测试默认手续费的 ETH 转账分配
    function testNativeTransferWithDefaultFee() public {
        uint256 transferAmount = 1 ether;
        uint256 expectedFeeAmount = (transferAmount * DEFAULT_FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;
        
        uint256 feeAddressBalanceBefore = feeAddress.balance;
        uint256 destAddressBalanceBefore = destAddress.balance;
        
        // 执行转账
        vm.prank(user);
        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);
        
        // 验证余额变化
        assertEq(feeAddress.balance, feeAddressBalanceBefore + expectedFeeAmount);
        assertEq(destAddress.balance, destAddressBalanceBefore + expectedDestAmount);
    }
    
    /// @notice 测试使用受益人列表的 ETH 转账分配
    function testNativeTransferWithBeneficiaryList() public {
        // 设置受益人列表：beneficiary1 20%, beneficiary2 30%，剩余 50% 给目标地址
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](2);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 2000 // 20%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 3000 // 30%
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        uint256 transferAmount = 1 ether;
        uint256 expectedBeneficiary1Amount = (transferAmount * 2000) / PERCENTAGE_BASE; // 0.2 ETH
        uint256 expectedBeneficiary2Amount = (transferAmount * 3000) / PERCENTAGE_BASE; // 0.3 ETH
        uint256 expectedDestAmount = transferAmount - expectedBeneficiary1Amount - expectedBeneficiary2Amount; // 0.5 ETH
        
        uint256 beneficiary1BalanceBefore = beneficiary1.balance;
        uint256 beneficiary2BalanceBefore = beneficiary2.balance;
        uint256 destAddressBalanceBefore = destAddress.balance;
        
        // 执行转账
        vm.prank(user);
        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);
        
        // 验证余额变化
        assertEq(beneficiary1.balance, beneficiary1BalanceBefore + expectedBeneficiary1Amount);
        assertEq(beneficiary2.balance, beneficiary2BalanceBefore + expectedBeneficiary2Amount);
        assertEq(destAddress.balance, destAddressBalanceBefore + expectedDestAmount);
    }
    
    /// @notice 测试 100% 分配给受益人的情况
    function testNativeTransferFullBeneficiaryAllocation() public {
        // 设置受益人列表：beneficiary1 60%, beneficiary2 40%，总计 100%
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](2);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 6000 // 60%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 4000 // 40%
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        uint256 transferAmount = 1 ether;
        uint256 expectedBeneficiary1Amount = (transferAmount * 6000) / PERCENTAGE_BASE; // 0.6 ETH
        uint256 expectedBeneficiary2Amount = (transferAmount * 4000) / PERCENTAGE_BASE; // 0.4 ETH
        
        uint256 beneficiary1BalanceBefore = beneficiary1.balance;
        uint256 beneficiary2BalanceBefore = beneficiary2.balance;
        uint256 destAddressBalanceBefore = destAddress.balance;
        
        // 执行转账
        vm.prank(user);
        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);
        
        // 验证余额变化
        assertEq(beneficiary1.balance, beneficiary1BalanceBefore + expectedBeneficiary1Amount);
        assertEq(beneficiary2.balance, beneficiary2BalanceBefore + expectedBeneficiary2Amount);
        assertEq(destAddress.balance, destAddressBalanceBefore); // 目标地址不应收到任何资金
    }
    
    /// @notice 测试默认手续费的 ERC20 代币转账分配
    function testERC20TransferWithDefaultFee() public {
        uint256 transferAmount = 1000 * 10**18;
        uint256 expectedFeeAmount = (transferAmount * DEFAULT_FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;
        
        uint256 feeAddressBalanceBefore = mockToken.balanceOf(feeAddress);
        uint256 destAddressBalanceBefore = mockToken.balanceOf(destAddress);
        
        // 执行代币转账
        vm.prank(user);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, transferAmount);
        
        // 验证余额变化
        assertEq(mockToken.balanceOf(feeAddress), feeAddressBalanceBefore + expectedFeeAmount);
        assertEq(mockToken.balanceOf(destAddress), destAddressBalanceBefore + expectedDestAmount);
    }
    
    /// @notice 测试使用受益人列表的 ERC20 代币转账分配
    function testERC20TransferWithBeneficiaryList() public {
        // 设置受益人列表
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](2);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 2500 // 25%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 2500 // 25%
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        uint256 transferAmount = 1000 * 10**18;
        uint256 expectedBeneficiary1Amount = (transferAmount * 2500) / PERCENTAGE_BASE; // 25%
        uint256 expectedBeneficiary2Amount = (transferAmount * 2500) / PERCENTAGE_BASE; // 25%
        uint256 expectedDestAmount = transferAmount - expectedBeneficiary1Amount - expectedBeneficiary2Amount; // 50%
        
        uint256 beneficiary1BalanceBefore = mockToken.balanceOf(beneficiary1);
        uint256 beneficiary2BalanceBefore = mockToken.balanceOf(beneficiary2);
        uint256 destAddressBalanceBefore = mockToken.balanceOf(destAddress);
        
        // 执行代币转账
        vm.prank(user);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, transferAmount);
        
        // 验证余额变化
        assertEq(mockToken.balanceOf(beneficiary1), beneficiary1BalanceBefore + expectedBeneficiary1Amount);
        assertEq(mockToken.balanceOf(beneficiary2), beneficiary2BalanceBefore + expectedBeneficiary2Amount);
        assertEq(mockToken.balanceOf(destAddress), destAddressBalanceBefore + expectedDestAmount);
    }
    
    /// @notice 测试分配金额计算功能
    function testCalculateDistributions() public {
        uint256 totalAmount = 1000 * 10**18;
        
        // 测试默认手续费计算
        FundsDividerV2.Distribution[] memory defaultDistributions = fundsDivider.calculateDistributions(destAddress, totalAmount);
        assertEq(defaultDistributions.length, 2);
        assertEq(defaultDistributions[0].recipient, feeAddress);
        assertEq(defaultDistributions[0].amount, (totalAmount * DEFAULT_FEE_PERCENTAGE) / PERCENTAGE_BASE);
        assertTrue(defaultDistributions[0].isDefault);
        assertEq(defaultDistributions[1].recipient, destAddress);
        assertEq(defaultDistributions[1].amount, totalAmount - defaultDistributions[0].amount);
        assertTrue(defaultDistributions[1].isDefault);
        
        // 设置受益人列表并测试计算
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](2);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 3000 // 30%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 2000 // 20%
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        FundsDividerV2.Distribution[] memory beneficiaryDistributions = fundsDivider.calculateDistributions(destAddress, totalAmount);
        assertEq(beneficiaryDistributions.length, 3); // 2 受益人 + 1 目标地址
        
        // 验证受益人分配
        assertEq(beneficiaryDistributions[0].recipient, beneficiary1);
        assertEq(beneficiaryDistributions[0].amount, (totalAmount * 3000) / PERCENTAGE_BASE);
        assertTrue(!beneficiaryDistributions[0].isDefault);
        
        assertEq(beneficiaryDistributions[1].recipient, beneficiary2);
        assertEq(beneficiaryDistributions[1].amount, (totalAmount * 2000) / PERCENTAGE_BASE);
        assertTrue(!beneficiaryDistributions[1].isDefault);
        
        // 验证目标地址剩余分配
        assertEq(beneficiaryDistributions[2].recipient, destAddress);
        assertEq(beneficiaryDistributions[2].amount, (totalAmount * 5000) / PERCENTAGE_BASE); // 剩余 50%
        assertTrue(beneficiaryDistributions[2].isDefault);
    }
    
    /// @notice 测试错误条件
    function testErrorConditions() public {
        // 测试无效地址
        vm.prank(user);
        vm.expectRevert(FundsDividerV2.InvalidAddress.selector);
        fundsDivider.divideNativeTransfer{value: 1 ether}(address(0));
        
        // 测试无效金额
        vm.prank(user);
        vm.expectRevert(FundsDividerV2.InvalidAmount.selector);
        fundsDivider.divideNativeTransfer{value: 0}(destAddress);
        
        // 测试余额不足
        address poorUser = address(0x99);
        vm.prank(poorUser);
        vm.expectRevert(FundsDividerV2.InsufficientBalance.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, 1000 * 10**18);
    }
    
    /// @notice 测试事件发送
    function testEvents() public {
        // 测试管理员更新事件
        address newAdmin = address(0x10);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit FundsDividerV2.AdminUpdated(admin, newAdmin);
        fundsDivider.updateAdmin(newAdmin);
        
        // 测试手续费地址更新事件
        address newFeeAddress = address(0x11);
        vm.prank(newAdmin);
        vm.expectEmit(true, true, false, true);
        emit FundsDividerV2.FeeAddressUpdated(feeAddress, newFeeAddress);
        fundsDivider.updateFeeAddress(newFeeAddress);
        
        // 测试受益人列表更新事件
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](1);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 1000
        });
        
        vm.prank(newAdmin);
        vm.expectEmit(true, false, false, true);
        emit FundsDividerV2.BeneficiaryListUpdated(destAddress, beneficiaries);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
    }
    
    /// @notice 测试复杂的受益人分配场景
    function testComplexBeneficiaryScenario() public {
        // 设置复杂的受益人列表：3 个受益人，总计 85%
        FundsDividerV2.Beneficiary[] memory beneficiaries = new FundsDividerV2.Beneficiary[](3);
        beneficiaries[0] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary1,
            percentage: 3500 // 35%
        });
        beneficiaries[1] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary2,
            percentage: 2500 // 25%
        });
        beneficiaries[2] = FundsDividerV2.Beneficiary({
            beneficiary: beneficiary3,
            percentage: 2500 // 25%
        });
        
        vm.prank(admin);
        fundsDivider.setBeneficiaryList(destAddress, beneficiaries);
        
        uint256 transferAmount = 2 ether;
        
        uint256 beneficiary1BalanceBefore = beneficiary1.balance;
        uint256 beneficiary2BalanceBefore = beneficiary2.balance;
        uint256 beneficiary3BalanceBefore = beneficiary3.balance;
        uint256 destAddressBalanceBefore = destAddress.balance;
        
        // 执行转账
        vm.prank(user);
        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);
        
        // 验证分配结果
        uint256 expectedBeneficiary1Amount = (transferAmount * 3500) / PERCENTAGE_BASE; // 0.7 ETH
        uint256 expectedBeneficiary2Amount = (transferAmount * 2500) / PERCENTAGE_BASE; // 0.5 ETH
        uint256 expectedBeneficiary3Amount = (transferAmount * 2500) / PERCENTAGE_BASE; // 0.5 ETH
        uint256 expectedDestAmount = (transferAmount * 1500) / PERCENTAGE_BASE; // 0.3 ETH (剩余 15%)
        
        assertEq(beneficiary1.balance, beneficiary1BalanceBefore + expectedBeneficiary1Amount);
        assertEq(beneficiary2.balance, beneficiary2BalanceBefore + expectedBeneficiary2Amount);
        assertEq(beneficiary3.balance, beneficiary3BalanceBefore + expectedBeneficiary3Amount);
        assertEq(destAddress.balance, destAddressBalanceBefore + expectedDestAmount);
        
        // 验证总金额守恒
        uint256 totalDistributed = expectedBeneficiary1Amount + expectedBeneficiary2Amount + 
                                  expectedBeneficiary3Amount + expectedDestAmount;
        assertEq(totalDistributed, transferAmount);
    }
}
