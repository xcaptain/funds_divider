# Intuipay Funds Divider & CrowdFunding

This repository contains two main smart contracts:

1. **IntuipayFundsDivider**: A contract for automatic fund division with fee collection
2. **CrowdFunding**: A blockchain-based donation platform for universities and research institutions

## IntuipayFundsDivider

EVM转账有2种形式，native token transfer 和 ERC20 token transfer

我希望创建一个叫 `FundsDivider` 的合约，通过这个合约进行转账，自动将 3% 的转账金额分配给 feeAddress，剩余部分分配给 destAddress

## CrowdFunding

### 功能概述

CrowdFunding 合约为大学和科研机构提供基于区块链的捐款平台，支持：

- 🎯 **活动创建**: 管理员可以为机构创建募资活动，设定目标金额和期限
- 💰 **智能捐款**: 用户可以向感兴趣的活动进行捐款（支持 ETH 和 ERC20 代币）
- 🔄 **自动状态管理**: 自动检查活动是否达成目标或超过期限
- 💸 **资金提取**: 成功活动的资金自动转给受益人（扣除平台费用）
- 🔄 **退款机制**: 失败活动的捐款自动退还给用户
- 🛡️ **安全保障**: 防重入攻击、权限控制、全面的参数验证

### 主要特性

#### 🏗️ 智能合约架构
- 使用 OpenZeppelin 的 `Ownable` 进行权限管理
- 基于 Solidity 0.8.13 开发，内置溢出检查
- 模块化设计，易于维护和升级

#### 📊 活动管理
- 活动状态：Active（活跃）、Successful（成功）、Failed（失败）
- 详细的活动信息存储：标题、描述、受益人、目标金额、截止时间、代币类型
- 贡献者记录和贡献金额追踪
- 支持 ETH 和 ERC20 代币捐款

#### 💰 费用机制
- 可配置的平台费用（默认 2.5%）
- 仅在活动成功时收取费用
- 透明的费用计算和分配

#### 🔒 安全措施
- 防重入攻击保护
- 严格的输入验证
- 自定义错误消息，节省 gas
- 紧急提取功能（仅管理员）

### 使用流程

1. **创建活动**: 管理员调用 `createCampaign()` 为机构创建募资活动
2. **用户捐款**: 用户调用 `contribute()` 或 `contributeERC20()` 向活动捐款
3. **状态检查**: 任何人可调用 `checkCampaignStatus()` 检查活动状态
4. **成功提取**: 活动成功后，受益人调用 `withdrawFunds()` 提取资金
5. **失败退款**: 活动失败后，捐款人调用 `requestRefund()` 申请退款

### 管理功能

- `createCampaign()`: 管理员创建新的募资活动（仅管理员）
- `updatePlatformAddress()`: 更新平台费用接收地址
- `updatePlatformFeePercentage()`: 更新平台费用比例
- `emergencyWithdraw()`: 紧急情况下提取合约资金

### 查询功能

- `getCampaignDetails()`: 获取活动详细信息
- `getUserContribution()`: 查询用户对特定活动的捐款
- `getCampaignContributors()`: 获取活动所有捐款人
- `calculateAmounts()`: 计算平台费用和净金额

## 部署

### IntuipayFundsDivider

```shell
# 加载环境变量
source .env

# 部署和验证
forge script --chain sepolia script/IntuipayFundsDivider.s.sol:DeployIntuipayFundsDivider --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv

# 部署到 edu-testnet
forge script script/IntuipayFundsDivider.s.sol:DeployIntuipayFundsDivider --broadcast --verify -vvvv --rpc-url https://rpc.open-campus-codex.gelato.digital
```

### CrowdFunding

```shell
# 设置环境变量
export PRIVATE_KEY="your_private_key"
export PLATFORM_ADDRESS="platform_fee_address"

# 部署 CrowdFunding 合约
forge script script/CrowdFunding.s.sol:CrowdFundingScript --rpc-url $RPC_URL --broadcast --verify -vvvv
```

## 更新 ABI 文件

```shell
# IntuipayFundsDivider
cat out/IntuipayFundsDivider.sol/IntuipayFundsDivider.json | jq ".abi" > IntuipayFundsDivider.abi.json

# CrowdFunding
cat out/CrowdFunding.sol/CrowdFunding.json | jq ".abi" > CrowdFunding.abi.json
```

## 测试

```shell
# 运行所有测试
forge test

# 运行特定合约测试
forge test --match-contract CrowdFundingTest -vv
forge test --match-contract IntuipayFundsDividerTest -vv

# 运行特定测试函数
forge test --match-test test_CreateCampaign -vv
forge test --match-test test_ContributeERC20 -vv
```

## 已部署的网络

### IntuipayFundsDivider

| 区块链网络 | 合约地址 | 手续费地址 | 管理员地址 |
| --- | --- | --- | --- |
| Ethereum Sepolia | [0xfeec3028af62b78e0d54f650063e1800ac7dfd98](https://sepolia.etherscan.io/address/0xfeec3028af62b78e0d54f650063e1800ac7dfd98) | 0x720aC46FdB6da28FA751bc60AfB8094290c2B4b7 | 0x7e727520B29773e7F23a8665649197aAf064CeF1 |
| Pharos Testnet | [0x6c81708c36A37D0CF527fF9b0a2eC98249a84257](https://testnet.pharosscan.xyz/address/0x6c81708c36a37d0cf527ff9b0a2ec98249a84257) | 0x6c81708c36a37d0cf527ff9b0a2ec98249a84257 |

### CrowdFunding

| 区块链网络 | 合约地址 | 平台地址 | 管理员地址 |
| --- | --- | --- | --- |
| TBD | TBD | TBD | TBD |

## 许可证

This project is licensed under the MIT License.
