// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

/// @title ERC20 接口
/// @notice 用于与 ERC20 代币交互的最小接口
interface IERC20 {
    /// @notice 转移代币到指定地址
    /// @param to 接收方地址
    /// @param amount 转移数量
    /// @return 是否成功
    function transfer(address to, uint256 amount) external returns (bool);
    
    /// @notice 从指定地址转移代币到另一个地址
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param amount 转移数量
    /// @return 是否成功
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    /// @notice 查询地址的代币余额
    /// @param account 要查询的地址
    /// @return 余额
    function balanceOf(address account) external view returns (uint256);
}

/// @title 资金分配器
/// @notice 用于自动分配转账资金的合约，扣除 3% 作为手续费
/// @dev 支持 ETH 和 ERC20 代币的转账分配
/// @author FundsDivider Team
contract FundsDivider {
    /// @notice 接收手续费的地址
    /// @dev 这个地址接收所有转账的 3% 手续费
    address public feeAddress;
    
    /// @notice 手续费百分比（3%）
    uint256 public constant FEE_PERCENTAGE = 3;
    
    /// @notice 百分比计算基数（100）
    uint256 public constant PERCENTAGE_BASE = 100;
    
    /// @notice ETH 转账完成事件
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param totalAmount 总转账金额
    /// @param feeAmount 手续费金额
    /// @param destAmount 实际到账金额
    event NativeTransfer(address indexed from, address indexed to, uint256 totalAmount, uint256 feeAmount, uint256 destAmount);
    
    /// @notice ERC20 代币转账完成事件
    /// @param token 代币合约地址
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param totalAmount 总转账金额
    /// @param feeAmount 手续费金额
    /// @param destAmount 实际到账金额
    event ERC20Transfer(address indexed token, address indexed from, address indexed to, uint256 totalAmount, uint256 feeAmount, uint256 destAmount);
    
    /// @notice 手续费地址更新事件
    /// @param oldFeeAddress 旧的手续费地址
    /// @param newFeeAddress 新的手续费地址
    event FeeAddressUpdated(address indexed oldFeeAddress, address indexed newFeeAddress);
    
    /// @notice 地址无效错误
    error InvalidAddress();
    
    /// @notice 金额无效错误
    error InvalidAmount();
    
    /// @notice 转账失败错误
    error TransferFailed();
    
    /// @notice 余额不足错误
    error InsufficientBalance();
    
    /// @notice 验证地址有效性的修饰符
    /// @param addr 要验证的地址
    modifier onlyValidAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }
    
    /// @notice 验证金额有效性的修饰符
    /// @param amount 要验证的金额
    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }
    
    /// @notice 构造函数
    /// @param _feeAddress 接收手续费的地址
    constructor(address _feeAddress) onlyValidAddress(_feeAddress) {
        feeAddress = _feeAddress;
    }
    
    /// @notice 更新手续费接收地址
    /// @dev 只有合约部署者可以调用此函数
    /// @param _newFeeAddress 新的手续费接收地址
    function updateFeeAddress(address _newFeeAddress) external onlyValidAddress(_newFeeAddress) {
        address oldFeeAddress = feeAddress;
        feeAddress = _newFeeAddress;
        emit FeeAddressUpdated(oldFeeAddress, _newFeeAddress);
    }
    
    /// @notice 分配 ETH 转账，扣除 3% 手续费
    /// @dev 自动将 3% 发送给手续费地址，97% 发送给目标地址
    /// @param destAddress 最终接收资金的地址
    function divideNativeTransfer(address destAddress) 
        external 
        payable 
        onlyValidAddress(destAddress) 
        onlyValidAmount(msg.value) 
    {
        uint256 totalAmount = msg.value;
        uint256 feeAmount = (totalAmount * FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 destAmount = totalAmount - feeAmount;
        
        // 转账给费用地址
        (bool feeSuccess, ) = feeAddress.call{value: feeAmount}("");
        if (!feeSuccess) revert TransferFailed();
        
        // 转账给目标地址
        (bool destSuccess, ) = destAddress.call{value: destAmount}("");
        if (!destSuccess) revert TransferFailed();
        
        emit NativeTransfer(msg.sender, destAddress, totalAmount, feeAmount, destAmount);
    }
    
    // ERC20 代币转账分配
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
        
        // 检查调用者的代币余额
        if (token.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        
        uint256 feeAmount = (amount * FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 destAmount = amount - feeAmount;
        
        // 从调用者转账费用部分到费用地址
        bool feeSuccess = token.transferFrom(msg.sender, feeAddress, feeAmount);
        if (!feeSuccess) revert TransferFailed();
        
        // 从调用者转账剩余部分到目标地址
        bool destSuccess = token.transferFrom(msg.sender, destAddress, destAmount);
        if (!destSuccess) revert TransferFailed();
        
        emit ERC20Transfer(tokenAddress, msg.sender, destAddress, amount, feeAmount, destAmount);
    }
    
    // 计算费用和目标金额
    function calculateAmounts(uint256 totalAmount) external pure returns (uint256 feeAmount, uint256 destAmount) {
        feeAmount = (totalAmount * FEE_PERCENTAGE) / PERCENTAGE_BASE;
        destAmount = totalAmount - feeAmount;
    }
}
