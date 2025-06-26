// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/FundsDivider.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000 * 10**18;
    
    constructor() {
        balanceOf[msg.sender] = totalSupply;
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
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract FundsDividerTest is Test {
    FundsDivider public fundsDivider;
    MockERC20 public mockToken;
    
    address public feeAddress = address(0x1);
    address public destAddress = address(0x2);
    address public user = address(0x3);
    
    function setUp() public {
        fundsDivider = new FundsDivider(feeAddress);
        mockToken = new MockERC20();
        
        // Give some ETH to test addresses
        vm.deal(user, 10 ether);
        vm.deal(destAddress, 1 ether);
        vm.deal(feeAddress, 1 ether);
        
        // Give some tokens to user
        mockToken.mint(user, 1000 * 10**18);
    }
    
    function testConstructor() public {
        assertEq(fundsDivider.feeAddress(), feeAddress);
        assertEq(fundsDivider.FEE_PERCENTAGE(), 3);
        assertEq(fundsDivider.PERCENTAGE_BASE(), 100);
    }
    
    function testConstructorWithZeroAddress() public {
        vm.expectRevert(FundsDivider.InvalidAddress.selector);
        new FundsDivider(address(0));
    }
    
    function testUpdateFeeAddress() public {
        address newFeeAddress = address(0x4);
        
        vm.expectEmit(true, true, false, true);
        emit FeeAddressUpdated(feeAddress, newFeeAddress);
        
        fundsDivider.updateFeeAddress(newFeeAddress);
        assertEq(fundsDivider.feeAddress(), newFeeAddress);
    }
    
    function testUpdateFeeAddressWithZeroAddress() public {
        vm.expectRevert(FundsDivider.InvalidAddress.selector);
        fundsDivider.updateFeeAddress(address(0));
    }
    
    function testNativeTransfer() public {
        uint256 transferAmount = 1 ether;
        uint256 expectedFeeAmount = (transferAmount * 3) / 100; // 3%
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;
        
        uint256 feeBalanceBefore = feeAddress.balance;
        uint256 destBalanceBefore = destAddress.balance;
        
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit NativeTransfer(user, destAddress, transferAmount, expectedFeeAmount, expectedDestAmount);
        
        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);
        
        assertEq(feeAddress.balance, feeBalanceBefore + expectedFeeAmount);
        assertEq(destAddress.balance, destBalanceBefore + expectedDestAmount);
        assertEq(address(fundsDivider).balance, 0); // Contract should not hold any funds
    }
    
    function testNativeTransferWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(FundsDivider.InvalidAmount.selector);
        fundsDivider.divideNativeTransfer{value: 0}(destAddress);
    }
    
    function testNativeTransferWithZeroDestAddress() public {
        vm.prank(user);
        vm.expectRevert(FundsDivider.InvalidAddress.selector);
        fundsDivider.divideNativeTransfer{value: 1 ether}(address(0));
    }
    
    function testERC20Transfer() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 expectedFeeAmount = (transferAmount * 3) / 100; // 3%
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;
        
        // User approves the contract to spend tokens
        vm.prank(user);
        mockToken.approve(address(fundsDivider), transferAmount);
        
        uint256 feeBalanceBefore = mockToken.balanceOf(feeAddress);
        uint256 destBalanceBefore = mockToken.balanceOf(destAddress);
        uint256 userBalanceBefore = mockToken.balanceOf(user);
        
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ERC20Transfer(address(mockToken), user, destAddress, transferAmount, expectedFeeAmount, expectedDestAmount);
        
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, transferAmount);
        
        assertEq(mockToken.balanceOf(feeAddress), feeBalanceBefore + expectedFeeAmount);
        assertEq(mockToken.balanceOf(destAddress), destBalanceBefore + expectedDestAmount);
        assertEq(mockToken.balanceOf(user), userBalanceBefore - transferAmount);
        assertEq(mockToken.balanceOf(address(fundsDivider)), 0); // Contract should not hold any tokens
    }
    
    function testERC20TransferWithInsufficientBalance() public {
        uint256 transferAmount = 2000 * 10**18; // More than user has
        
        vm.prank(user);
        mockToken.approve(address(fundsDivider), transferAmount);
        
        vm.prank(user);
        vm.expectRevert(FundsDivider.InsufficientBalance.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, transferAmount);
    }
    
    function testERC20TransferWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(FundsDivider.InvalidAmount.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, 0);
    }
    
    function testERC20TransferWithZeroTokenAddress() public {
        vm.prank(user);
        vm.expectRevert(FundsDivider.InvalidAddress.selector);
        fundsDivider.divideERC20Transfer(address(0), destAddress, 100);
    }
    
    function testERC20TransferWithZeroDestAddress() public {
        vm.prank(user);
        vm.expectRevert(FundsDivider.InvalidAddress.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), address(0), 100);
    }
    
    function testCalculateAmounts() public {
        uint256 totalAmount = 1000;
        (uint256 feeAmount, uint256 destAmount) = fundsDivider.calculateAmounts(totalAmount);
        
        assertEq(feeAmount, 30); // 3% of 1000
        assertEq(destAmount, 970); // 97% of 1000
        assertEq(feeAmount + destAmount, totalAmount);
    }
    
    function testCalculateAmountsWithVariousValues() public {
        // Test with 1 ether
        (uint256 feeAmount1, uint256 destAmount1) = fundsDivider.calculateAmounts(1 ether);
        assertEq(feeAmount1, 0.03 ether);
        assertEq(destAmount1, 0.97 ether);
        
        // Test with 100
        (uint256 feeAmount2, uint256 destAmount2) = fundsDivider.calculateAmounts(100);
        assertEq(feeAmount2, 3);
        assertEq(destAmount2, 97);
        
        // Test edge case with small amount
        (uint256 feeAmount3, uint256 destAmount3) = fundsDivider.calculateAmounts(33);
        assertEq(feeAmount3, 0); // 33 * 3 / 100 = 0 (integer division)
        assertEq(destAmount3, 33);
    }
    
    // Events for testing
    event NativeTransfer(address indexed from, address indexed to, uint256 totalAmount, uint256 feeAmount, uint256 destAmount);
    event ERC20Transfer(address indexed token, address indexed from, address indexed to, uint256 totalAmount, uint256 feeAmount, uint256 destAmount);
    event FeeAddressUpdated(address indexed oldFeeAddress, address indexed newFeeAddress);
}
