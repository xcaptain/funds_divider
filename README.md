# funds divider

evm转账有2种形式，native token transfer 和 ERC20 token transfer

我希望创建一个叫 `FundsDivider` 的合约，通过这个合约进行转账，自动将 3% 的转账金额分配给 feeAddress，剩余部分分配给 destAddress

