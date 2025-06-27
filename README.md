# funds divider

evm转账有2种形式，native token transfer 和 ERC20 token transfer

我希望创建一个叫 `FundsDivider` 的合约，通过这个合约进行转账，自动将 3% 的转账金额分配给 feeAddress，剩余部分分配给 destAddress

## 部署

```shell
# 加载环境变量
source .env

# 部署和验证
forge script --chain sepolia script/IntuipayFundsDivider.s.sol:DeployIntuipayFundsDivider --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
```

## 更新 abi 文件

```shell
cat out/IntuipayFundsDivider.sol/IntuipayFundsDivider.json | jq ".abi" > IntuipayFundsDivider.abi.json
```

## 已部署的网络

| 区块链网络 | 合约地址 | 手续费地址 | 管理员地址 |
| --- | --- | --- | --- |
| Ethereum Sepolia | [0xfeec3028af62b78e0d54f650063e1800ac7dfd98](https://sepolia.etherscan.io/address/0xfeec3028af62b78e0d54f650063e1800ac7dfd98) | 0x720aC46FdB6da28FA751bc60AfB8094290c2B4b7 | 0x7e727520B29773e7F23a8665649197aAf064CeF1 |
