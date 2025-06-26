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

/// @title 资金分配器 V2
/// @notice 用于自动分配转账资金的合约，支持为每个目标地址配置受益人列表
/// @dev 支持 ETH 和 ERC20 代币的转账分配，管理员可以为每个目标地址配置受益人分配比例
/// @author FundsDivider Team
contract FundsDividerV2 {
    /// @notice 受益人信息结构体
    /// @param beneficiary 受益人地址
    /// @param percentage 分配百分比（基数为 10000，即 100 表示 1%）
    struct Beneficiary {
        address beneficiary;
        uint256 percentage;
    }
    
    /// @notice 合约管理员地址
    address public admin;
    
    /// @notice 接收手续费的地址
    /// @dev 这个地址接收所有转账的默认手续费
    address public feeAddress;
    
    /// @notice 默认手续费百分比（3%）
    uint256 public constant DEFAULT_FEE_PERCENTAGE = 300; // 300/10000 = 3%
    
    /// @notice 百分比计算基数（10000，支持小数点后两位）
    uint256 public constant PERCENTAGE_BASE = 10000;
    
    /// @notice 目标地址的受益人列表映射
    /// @dev destAddress => Beneficiary[]
    mapping(address => Beneficiary[]) public beneficiaryLists;
    
    /// @notice 检查目标地址是否已配置受益人列表
    mapping(address => bool) public hasBeneficiaryList;
    
    /// @notice ETH 转账完成事件
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param totalAmount 总转账金额
    /// @param distributions 分配详情数组
    event NativeTransfer(
        address indexed from, 
        address indexed to, 
        uint256 totalAmount, 
        Distribution[] distributions
    );
    
    /// @notice ERC20 代币转账完成事件
    /// @param token 代币合约地址
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param totalAmount 总转账金额
    /// @param distributions 分配详情数组
    event ERC20Transfer(
        address indexed token,
        address indexed from, 
        address indexed to, 
        uint256 totalAmount, 
        Distribution[] distributions
    );
    
    /// @notice 受益人列表更新事件
    /// @param destAddress 目标地址
    /// @param beneficiaries 新的受益人列表
    event BeneficiaryListUpdated(address indexed destAddress, Beneficiary[] beneficiaries);
    
    /// @notice 手续费地址更新事件
    /// @param oldFeeAddress 旧的手续费地址
    /// @param newFeeAddress 新的手续费地址
    event FeeAddressUpdated(address indexed oldFeeAddress, address indexed newFeeAddress);
    
    /// @notice 管理员更新事件
    /// @param oldAdmin 旧的管理员地址
    /// @param newAdmin 新的管理员地址
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    
    /// @notice 分配详情结构体
    /// @param recipient 接收方地址
    /// @param amount 分配金额
    /// @param isDefault 是否为默认分配（非受益人分配）
    struct Distribution {
        address recipient;
        uint256 amount;
        bool isDefault;
    }
    
    /// @notice 地址无效错误
    error InvalidAddress();
    
    /// @notice 金额无效错误
    error InvalidAmount();
    
    /// @notice 转账失败错误
    error TransferFailed();
    
    /// @notice 余额不足错误
    error InsufficientBalance();
    
    /// @notice 权限不足错误
    error Unauthorized();
    
    /// @notice 百分比总和无效错误
    error InvalidPercentageSum();
    
    /// @notice 受益人列表为空错误
    error EmptyBeneficiaryList();
    
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
    
    /// @notice 只有管理员可以调用的修饰符
    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }
    
    /// @notice 构造函数
    /// @param _admin 管理员地址
    /// @param _feeAddress 接收手续费的地址
    constructor(address _admin, address _feeAddress) 
        onlyValidAddress(_admin) 
        onlyValidAddress(_feeAddress) 
    {
        admin = _admin;
        feeAddress = _feeAddress;
    }
    
    /// @notice 更新管理员地址
    /// @param _newAdmin 新的管理员地址
    function updateAdmin(address _newAdmin) external onlyAdmin onlyValidAddress(_newAdmin) {
        address oldAdmin = admin;
        admin = _newAdmin;
        emit AdminUpdated(oldAdmin, _newAdmin);
    }
    
    /// @notice 更新手续费接收地址
    /// @param _newFeeAddress 新的手续费接收地址
    function updateFeeAddress(address _newFeeAddress) external onlyAdmin onlyValidAddress(_newFeeAddress) {
        address oldFeeAddress = feeAddress;
        feeAddress = _newFeeAddress;
        emit FeeAddressUpdated(oldFeeAddress, _newFeeAddress);
    }
    
    /// @notice 为目标地址设置受益人列表
    /// @param destAddress 目标地址
    /// @param beneficiaries 受益人列表
    function setBeneficiaryList(address destAddress, Beneficiary[] calldata beneficiaries) 
        external 
        onlyAdmin 
        onlyValidAddress(destAddress) 
    {
        if (beneficiaries.length == 0) revert EmptyBeneficiaryList();
        
        // 验证百分比总和不超过 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i].beneficiary == address(0)) revert InvalidAddress();
            totalPercentage += beneficiaries[i].percentage;
        }
        if (totalPercentage > PERCENTAGE_BASE) revert InvalidPercentageSum();
        
        // 清空现有列表
        delete beneficiaryLists[destAddress];
        
        // 添加新的受益人列表
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            beneficiaryLists[destAddress].push(beneficiaries[i]);
        }
        
        hasBeneficiaryList[destAddress] = true;
        emit BeneficiaryListUpdated(destAddress, beneficiaries);
    }
    
    /// @notice 移除目标地址的受益人列表
    /// @param destAddress 目标地址
    function removeBeneficiaryList(address destAddress) external onlyAdmin {
        delete beneficiaryLists[destAddress];
        hasBeneficiaryList[destAddress] = false;
        
        // 发送空的受益人列表事件
        Beneficiary[] memory emptyList;
        emit BeneficiaryListUpdated(destAddress, emptyList);
    }
    
    /// @notice 获取目标地址的受益人列表
    /// @param destAddress 目标地址
    /// @return 受益人列表
    function getBeneficiaryList(address destAddress) external view returns (Beneficiary[] memory) {
        return beneficiaryLists[destAddress];
    }
    
    /// @notice 分配 ETH 转账，根据受益人列表或默认手续费进行分配
    /// @param destAddress 目标地址
    function divideNativeTransfer(address destAddress) 
        external 
        payable 
        onlyValidAddress(destAddress) 
        onlyValidAmount(msg.value) 
    {
        uint256 totalAmount = msg.value;
        Distribution[] memory distributions;
        
        if (hasBeneficiaryList[destAddress]) {
            // 使用受益人列表进行分配
            distributions = _distributeWithBeneficiaryList(destAddress, totalAmount, true);
        } else {
            // 使用默认手续费分配
            distributions = _distributeWithDefaultFee(destAddress, totalAmount, true);
        }
        
        emit NativeTransfer(msg.sender, destAddress, totalAmount, distributions);
    }
    
    /// @notice 分配 ERC20 代币转账，根据受益人列表或默认手续费进行分配
    /// @param tokenAddress 代币合约地址
    /// @param destAddress 目标地址
    /// @param amount 转账金额
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
        
        Distribution[] memory distributions;
        
        if (hasBeneficiaryList[destAddress]) {
            // 使用受益人列表进行分配
            distributions = _distributeWithBeneficiaryList(destAddress, amount, false);
        } else {
            // 使用默认手续费分配
            distributions = _distributeWithDefaultFee(destAddress, amount, false);
        }
        
        // 执行 ERC20 代币转账
        for (uint256 i = 0; i < distributions.length; i++) {
            bool success = token.transferFrom(msg.sender, distributions[i].recipient, distributions[i].amount);
            if (!success) revert TransferFailed();
        }
        
        emit ERC20Transfer(tokenAddress, msg.sender, destAddress, amount, distributions);
    }
    
    /// @notice 使用受益人列表进行分配
    /// @param destAddress 目标地址
    /// @param totalAmount 总金额
    /// @param isNative 是否为原生代币（ETH）
    /// @return distributions 分配详情数组
    function _distributeWithBeneficiaryList(
        address destAddress, 
        uint256 totalAmount, 
        bool isNative
    ) internal returns (Distribution[] memory distributions) {
        Beneficiary[] memory beneficiaries = beneficiaryLists[destAddress];
        
        // 计算受益人分配的总百分比
        uint256 beneficiaryTotalPercentage = 0;
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            beneficiaryTotalPercentage += beneficiaries[i].percentage;
        }
        
        // 创建分配数组
        uint256 distributionCount = beneficiaries.length;
        if (beneficiaryTotalPercentage < PERCENTAGE_BASE) {
            distributionCount++; // 为目标地址添加剩余金额
        }
        
        distributions = new Distribution[](distributionCount);
        
        uint256 distributedAmount = 0;
        uint256 index = 0;
        
        // 分配给受益人
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            uint256 beneficiaryAmount = (totalAmount * beneficiaries[i].percentage) / PERCENTAGE_BASE;
            distributions[index] = Distribution({
                recipient: beneficiaries[i].beneficiary,
                amount: beneficiaryAmount,
                isDefault: false
            });
            
            if (isNative) {
                (bool success, ) = beneficiaries[i].beneficiary.call{value: beneficiaryAmount}("");
                if (!success) revert TransferFailed();
            }
            
            distributedAmount += beneficiaryAmount;
            index++;
        }
        
        // 如果有剩余金额，分配给目标地址
        if (beneficiaryTotalPercentage < PERCENTAGE_BASE) {
            uint256 remainingAmount = totalAmount - distributedAmount;
            distributions[index] = Distribution({
                recipient: destAddress,
                amount: remainingAmount,
                isDefault: true
            });
            
            if (isNative) {
                (bool success, ) = destAddress.call{value: remainingAmount}("");
                if (!success) revert TransferFailed();
            }
        }
    }
    
    /// @notice 使用默认手续费进行分配
    /// @param destAddress 目标地址
    /// @param totalAmount 总金额
    /// @param isNative 是否为原生代币（ETH）
    /// @return distributions 分配详情数组
    function _distributeWithDefaultFee(
        address destAddress, 
        uint256 totalAmount, 
        bool isNative
    ) internal returns (Distribution[] memory distributions) {
        uint256 feeAmount = (totalAmount * DEFAULT_FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 destAmount = totalAmount - feeAmount;
        
        distributions = new Distribution[](2);
        
        // 手续费分配
        distributions[0] = Distribution({
            recipient: feeAddress,
            amount: feeAmount,
            isDefault: true
        });
        
        // 目标地址分配
        distributions[1] = Distribution({
            recipient: destAddress,
            amount: destAmount,
            isDefault: true
        });
        
        if (isNative) {
            // 转账给费用地址
            (bool feeSuccess, ) = feeAddress.call{value: feeAmount}("");
            if (!feeSuccess) revert TransferFailed();
            
            // 转账给目标地址
            (bool destSuccess, ) = destAddress.call{value: destAmount}("");
            if (!destSuccess) revert TransferFailed();
        }
    }
    
    /// @notice 计算分配金额（不执行转账）
    /// @param destAddress 目标地址
    /// @param totalAmount 总金额
    /// @return distributions 分配详情数组
    function calculateDistributions(address destAddress, uint256 totalAmount) 
        external 
        view 
        returns (Distribution[] memory distributions) 
    {
        if (hasBeneficiaryList[destAddress]) {
            return _calculateWithBeneficiaryList(destAddress, totalAmount);
        } else {
            return _calculateWithDefaultFee(destAddress, totalAmount);
        }
    }
    
    /// @notice 使用受益人列表计算分配（仅计算，不执行转账）
    function _calculateWithBeneficiaryList(
        address destAddress, 
        uint256 totalAmount
    ) internal view returns (Distribution[] memory distributions) {
        Beneficiary[] memory beneficiaries = beneficiaryLists[destAddress];
        
        // 计算受益人分配的总百分比
        uint256 beneficiaryTotalPercentage = 0;
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            beneficiaryTotalPercentage += beneficiaries[i].percentage;
        }
        
        // 创建分配数组
        uint256 distributionCount = beneficiaries.length;
        if (beneficiaryTotalPercentage < PERCENTAGE_BASE) {
            distributionCount++; // 为目标地址添加剩余金额
        }
        
        distributions = new Distribution[](distributionCount);
        
        uint256 distributedAmount = 0;
        uint256 index = 0;
        
        // 计算受益人分配
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            uint256 beneficiaryAmount = (totalAmount * beneficiaries[i].percentage) / PERCENTAGE_BASE;
            distributions[index] = Distribution({
                recipient: beneficiaries[i].beneficiary,
                amount: beneficiaryAmount,
                isDefault: false
            });
            distributedAmount += beneficiaryAmount;
            index++;
        }
        
        // 如果有剩余金额，分配给目标地址
        if (beneficiaryTotalPercentage < PERCENTAGE_BASE) {
            uint256 remainingAmount = totalAmount - distributedAmount;
            distributions[index] = Distribution({
                recipient: destAddress,
                amount: remainingAmount,
                isDefault: true
            });
        }
    }
    
    /// @notice 使用默认手续费计算分配（仅计算，不执行转账）
    function _calculateWithDefaultFee(
        address destAddress, 
        uint256 totalAmount
    ) internal view returns (Distribution[] memory distributions) {
        uint256 feeAmount = (totalAmount * DEFAULT_FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 destAmount = totalAmount - feeAmount;
        
        distributions = new Distribution[](2);
        
        // 手续费分配
        distributions[0] = Distribution({
            recipient: feeAddress,
            amount: feeAmount,
            isDefault: true
        });
        
        // 目标地址分配
        distributions[1] = Distribution({
            recipient: destAddress,
            amount: destAmount,
            isDefault: true
        });
    }
}
