// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Funds Divider
/// @notice Contract for automatically dividing transfer funds, deducting a 3% fee
/// @dev Supports transfer division for both ETH and ERC20 tokens
/// @author Intuipay Team
contract IntuipayFundsDivider is Ownable {
    /// @notice The address that receives the fees
    /// @dev This address receives the fees from all transfers
    address public feeAddress;

    /// @notice Fee percentage (configurable, based on 10000)
    uint256 public feePercentage = 300; // Default 3%

    /// @notice The base for percentage calculation (10000)
    uint256 public constant PERCENTAGE_BASE = 10000;

    /// @notice Event for completed ETH transfer
    /// @param from The sender address
    /// @param to The recipient address
    /// @param totalAmount The total transfer amount
    /// @param feeAmount The fee amount
    /// @param destAmount The actual amount received
    event NativeTransfer(
        address indexed from,
        address indexed to,
        uint256 totalAmount,
        uint256 feeAmount,
        uint256 destAmount
    );

    /// @notice Event for completed ERC20 token transfer
    /// @param token The token contract address
    /// @param from The sender address
    /// @param to The recipient address
    /// @param totalAmount The total transfer amount
    /// @param feeAmount The fee amount
    /// @param destAmount The actual amount received
    event ERC20Transfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 totalAmount,
        uint256 feeAmount,
        uint256 destAmount
    );

    /// @notice Event for fee address update
    /// @param oldFeeAddress The old fee address
    /// @param newFeeAddress The new fee address
    event FeeAddressUpdated(
        address indexed oldFeeAddress,
        address indexed newFeeAddress
    );

    /// @notice Event for fee percentage update
    /// @param oldFeePercentage The old fee percentage
    /// @param newFeePercentage The new fee percentage
    event FeePercentageUpdated(
        uint256 oldFeePercentage,
        uint256 newFeePercentage
    );

    /// @notice Error for invalid address
    error InvalidAddress();

    /// @notice Error for invalid amount
    error InvalidAmount();

    /// @notice Error for transfer failure
    error TransferFailed();

    /// @notice Error for insufficient balance
    error InsufficientBalance();

    /// @notice Error for unauthorized access
    error Unauthorized();

    /// @notice Error for invalid fee percentage
    error InvalidFeePercentage();

    /// @notice Modifier to validate an address
    /// @param addr The address to validate
    modifier onlyValidAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Modifier to validate an amount
    /// @param amount The amount to validate
    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /// @notice Constructor
    /// @param initialOwner The administrator address
    /// @param _feeAddress The address to receive fees
    constructor(
        address initialOwner,
        address _feeAddress
    ) Ownable(initialOwner) onlyValidAddress(_feeAddress) {
        feeAddress = _feeAddress;
    }

    /// @notice Updates the fee recipient address
    /// @param _newFeeAddress The new fee recipient address
    function updateFeeAddress(
        address _newFeeAddress
    ) external onlyOwner onlyValidAddress(_newFeeAddress) {
        address oldFeeAddress = feeAddress;
        feeAddress = _newFeeAddress;
        emit FeeAddressUpdated(oldFeeAddress, _newFeeAddress);
    }

    /// @notice Updates the fee percentage
    /// @param _newFeePercentage The new fee percentage (based on 10000, cannot exceed 100%)
    function updateFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        if (_newFeePercentage > PERCENTAGE_BASE) revert InvalidFeePercentage();
        uint256 oldFeePercentage = feePercentage;
        feePercentage = _newFeePercentage;
        emit FeePercentageUpdated(oldFeePercentage, _newFeePercentage);
    }

    /// @notice Divides ETH transfer and deducts a fee
    /// @dev Automatically sends the fee to the fee address and the remainder to the destination address
    /// @param destAddress The final address to receive funds
    function divideNativeTransfer(
        address destAddress
    )
        external
        payable
        onlyValidAddress(destAddress)
        onlyValidAmount(msg.value)
    {
        uint256 totalAmount = msg.value;
        uint256 feeAmount = (totalAmount * feePercentage) / PERCENTAGE_BASE;
        uint256 destAmount = totalAmount - feeAmount;

        // Transfer to the fee address
        (bool feeSuccess, ) = feeAddress.call{value: feeAmount}("");
        if (!feeSuccess) revert TransferFailed();

        // Transfer to the destination address
        (bool destSuccess, ) = destAddress.call{value: destAmount}("");
        if (!destSuccess) revert TransferFailed();

        emit NativeTransfer(
            msg.sender,
            destAddress,
            totalAmount,
            feeAmount,
            destAmount
        );
    }

    // ERC20 token transfer division
    function divideERC20Transfer(
        address tokenAddress,
        address destAddress,
        uint256 amount
    )
        external
        onlyValidAddress(tokenAddress)
        onlyValidAddress(destAddress)
        onlyValidAmount(amount)
    {
        IERC20 token = IERC20(tokenAddress);

        // Check the caller's token balance
        if (token.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        uint256 feeAmount = (amount * feePercentage) / PERCENTAGE_BASE;
        uint256 destAmount = amount - feeAmount;

        // Transfer the fee portion from the caller to the fee address
        bool feeSuccess = token.transferFrom(msg.sender, feeAddress, feeAmount);
        if (!feeSuccess) revert TransferFailed();

        // Transfer the remaining portion from the caller to the destination address
        bool destSuccess = token.transferFrom(
            msg.sender,
            destAddress,
            destAmount
        );
        if (!destSuccess) revert TransferFailed();

        emit ERC20Transfer(
            tokenAddress,
            msg.sender,
            destAddress,
            amount,
            feeAmount,
            destAmount
        );
    }

    /// @notice Calculates the fee and destination amounts
    /// @param totalAmount The total amount
    /// @return feeAmount The fee amount
    /// @return destAmount The destination address amount
    function calculateAmounts(
        uint256 totalAmount
    ) external view returns (uint256 feeAmount, uint256 destAmount) {
        feeAmount = (totalAmount * feePercentage) / PERCENTAGE_BASE;
        destAmount = totalAmount - feeAmount;
    }
}
