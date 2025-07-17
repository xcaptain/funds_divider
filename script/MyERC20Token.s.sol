// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MyERC20Token} from "../src/MyERC20Token.sol";

/// @title Deploy MyERC20Token
/// @notice A script to deploy the MyERC20Token contract.
/// @dev This script reads the deployer's private key and token parameters
///      from environment variables to deploy the contract.
contract DeployMyERC20Token is Script {
    function run() external returns (MyERC20Token) {
        // Get the deployer's private key from the PRIVATE_KEY environment variable.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get token parameters from environment variables
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Test USDC"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("TUSDC"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1000000)); // Default 1M tokens
        
        // Get the owner address from environment variable, default to deployer
        address owner = vm.envOr("TOKEN_OWNER", address(0));
        
        // The deployer's address will be the initial owner if not specified.
        address initialOwner = vm.addr(deployerPrivateKey);
        
        // If TOKEN_OWNER is not set, default to the deployer's address.
        if (owner == address(0)) {
            owner = initialOwner;
        }

        console.log("Deploying MyERC20Token...");
        console.log("  Token Name:     ", tokenName);
        console.log("  Token Symbol:   ", tokenSymbol);
        console.log("  Initial Supply: ", initialSupply);
        console.log("  Owner:          ", owner);
        console.log("  Deployer:       ", initialOwner);

        vm.startBroadcast(deployerPrivateKey);

        MyERC20Token token = new MyERC20Token(
            tokenName,
            tokenSymbol,
            initialSupply,
            owner
        );

        vm.stopBroadcast();

        console.log("MyERC20Token deployed to:", address(token));
        console.log("Total supply:", token.totalSupply());
        console.log("Owner balance:", token.balanceOf(owner));

        return token;
    }
}
