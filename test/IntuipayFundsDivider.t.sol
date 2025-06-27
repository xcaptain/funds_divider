// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IntuipayFundsDivider} from "../src/IntuipayFundsDivider.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    constructor() {
        totalSupply = 1000000 * 10 ** 18;
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract IntuipayFundsDividerTest is Test {
    IntuipayFundsDivider public fundsDivider;
    MockERC20 public mockToken;

    address public owner = address(0x1);
    address public feeAddress = address(0x2);
    address public destAddress = address(0x3);
    address public user = address(0x4);

    // Events for testing
    event NativeTransfer(
        address indexed from,
        address indexed to,
        uint256 totalAmount,
        uint256 feeAmount,
        uint256 destAmount
    );
    event ERC20Transfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 totalAmount,
        uint256 feeAmount,
        uint256 destAmount
    );
    event FeeAddressUpdated(
        address indexed oldFeeAddress,
        address indexed newFeeAddress
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event FeePercentageUpdated(
        uint256 oldFeePercentage,
        uint256 newFeePercentage
    );

    function setUp() public {
        vm.prank(owner);
        fundsDivider = new IntuipayFundsDivider(owner, feeAddress);
        mockToken = new MockERC20();

        // Give some ETH to test addresses
        vm.deal(user, 10 ether);
        vm.deal(destAddress, 1 ether);
        vm.deal(feeAddress, 1 ether);

        // Give some tokens to user
        mockToken.mint(user, 1000 * 10 ** 18);
    }

    function testConstructor() public {
        assertEq(fundsDivider.owner(), owner);
        assertEq(fundsDivider.feeAddress(), feeAddress);
        assertEq(fundsDivider.feePercentage(), 300); // Default 3%
        assertEq(fundsDivider.PERCENTAGE_BASE(), 10000);
    }

    function testConstructorWithZeroFeeAddress() public {
        vm.prank(owner);
        vm.expectRevert(IntuipayFundsDivider.InvalidAddress.selector);
        new IntuipayFundsDivider(owner, address(0));
    }

    function testTransferOwnership() public {
        address newOwner = address(0x5);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);

        fundsDivider.transferOwnership(newOwner);
        assertEq(fundsDivider.owner(), newOwner);
    }

    function testTransferOwnershipUnauthorized() public {
        address newOwner = address(0x5);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        fundsDivider.transferOwnership(newOwner);
    }

    function testUpdateFeeAddress() public {
        address newFeeAddress = address(0x5);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FeeAddressUpdated(feeAddress, newFeeAddress);

        fundsDivider.updateFeeAddress(newFeeAddress);
        assertEq(fundsDivider.feeAddress(), newFeeAddress);
    }

    function testUpdateFeeAddressUnauthorized() public {
        address newFeeAddress = address(0x5);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        fundsDivider.updateFeeAddress(newFeeAddress);
    }

    function testUpdateFeePercentage() public {
        uint256 newFeePercentage = 500; // 5%

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit FeePercentageUpdated(300, newFeePercentage);

        fundsDivider.updateFeePercentage(newFeePercentage);
        assertEq(fundsDivider.feePercentage(), newFeePercentage);
    }

    function testUpdateFeePercentageInvalid() public {
        uint256 invalidFeePercentage = 10001; // > 100%

        vm.prank(owner);
        vm.expectRevert(IntuipayFundsDivider.InvalidFeePercentage.selector);
        fundsDivider.updateFeePercentage(invalidFeePercentage);
    }

    function testUpdateFeePercentageUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        fundsDivider.updateFeePercentage(500);
    }

    function testUpdateFeeAddressWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IntuipayFundsDivider.InvalidAddress.selector);
        fundsDivider.updateFeeAddress(address(0));
    }

    function testNativeTransfer() public {
        uint256 transferAmount = 1 ether;
        uint256 expectedFeeAmount = (transferAmount * 300) / 10000; // 3%
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;

        uint256 feeBalanceBefore = feeAddress.balance;
        uint256 destBalanceBefore = destAddress.balance;

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit NativeTransfer(
            user,
            destAddress,
            transferAmount,
            expectedFeeAmount,
            expectedDestAmount
        );

        fundsDivider.divideNativeTransfer{value: transferAmount}(destAddress);

        assertEq(feeAddress.balance, feeBalanceBefore + expectedFeeAmount);
        assertEq(destAddress.balance, destBalanceBefore + expectedDestAmount);
        assertEq(address(fundsDivider).balance, 0); // Contract should not hold any funds
    }

    function testNativeTransferWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InvalidAmount.selector);
        fundsDivider.divideNativeTransfer{value: 0}(destAddress);
    }

    function testNativeTransferWithZeroDestAddress() public {
        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InvalidAddress.selector);
        fundsDivider.divideNativeTransfer{value: 1 ether}(address(0));
    }

    function testERC20Transfer() public {
        uint256 transferAmount = 100 * 10 ** 18;
        uint256 expectedFeeAmount = (transferAmount * 300) / 10000; // 3%
        uint256 expectedDestAmount = transferAmount - expectedFeeAmount;

        // User approves the contract to spend tokens
        vm.prank(user);
        mockToken.approve(address(fundsDivider), transferAmount);

        uint256 feeBalanceBefore = mockToken.balanceOf(feeAddress);
        uint256 destBalanceBefore = mockToken.balanceOf(destAddress);
        uint256 userBalanceBefore = mockToken.balanceOf(user);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ERC20Transfer(
            address(mockToken),
            user,
            destAddress,
            transferAmount,
            expectedFeeAmount,
            expectedDestAmount
        );

        fundsDivider.divideERC20Transfer(
            address(mockToken),
            destAddress,
            transferAmount
        );

        assertEq(
            mockToken.balanceOf(feeAddress),
            feeBalanceBefore + expectedFeeAmount
        );
        assertEq(
            mockToken.balanceOf(destAddress),
            destBalanceBefore + expectedDestAmount
        );
        assertEq(mockToken.balanceOf(user), userBalanceBefore - transferAmount);
        assertEq(mockToken.balanceOf(address(fundsDivider)), 0); // Contract should not hold any tokens
    }

    function testERC20TransferWithInsufficientBalance() public {
        uint256 transferAmount = 2000 * 10 ** 18; // More than user has

        vm.prank(user);
        mockToken.approve(address(fundsDivider), transferAmount);

        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InsufficientBalance.selector);
        fundsDivider.divideERC20Transfer(
            address(mockToken),
            destAddress,
            transferAmount
        );
    }

    function testERC20TransferWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InvalidAmount.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), destAddress, 0);
    }

    function testERC20TransferWithZeroTokenAddress() public {
        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InvalidAddress.selector);
        fundsDivider.divideERC20Transfer(address(0), destAddress, 100);
    }

    function testERC20TransferWithZeroDestAddress() public {
        vm.prank(user);
        vm.expectRevert(IntuipayFundsDivider.InvalidAddress.selector);
        fundsDivider.divideERC20Transfer(address(mockToken), address(0), 100);
    }

    function testCalculateAmounts() public {
        uint256 totalAmount = 1000;
        (uint256 feeAmount, uint256 destAmount) = fundsDivider.calculateAmounts(
            totalAmount
        );

        assertEq(feeAmount, 30); // 3% of 1000
        assertEq(destAmount, 970); // 97% of 1000
        assertEq(feeAmount + destAmount, totalAmount);
    }

    function testCalculateAmountsWithVariousValues() public {
        // Test with 1 ether
        (uint256 feeAmount1, uint256 destAmount1) = fundsDivider
            .calculateAmounts(1 ether);
        assertEq(feeAmount1, 0.03 ether);
        assertEq(destAmount1, 0.97 ether);

        // Test with 100
        (uint256 feeAmount2, uint256 destAmount2) = fundsDivider
            .calculateAmounts(100);
        assertEq(feeAmount2, 3);
        assertEq(destAmount2, 97);

        // Test edge case with small amount
        (uint256 feeAmount3, uint256 destAmount3) = fundsDivider
            .calculateAmounts(33);
        assertEq(feeAmount3, 0); // 33 * 300 / 10000 = 0 (integer division)
        assertEq(destAmount3, 33);
    }
}
