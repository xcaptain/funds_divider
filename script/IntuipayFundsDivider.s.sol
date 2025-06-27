// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IntuipayFundsDivider} from "../src/IntuipayFundsDivider.sol";

/// @title Deploy IntuipayFundsDivider
/// @notice A script to deploy the IntuipayFundsDivider contract.
/// @dev This script reads the deployer's private key and the fee address
///      from environment variables to deploy the contract.
contract DeployIntuipayFundsDivider is Script {
    function run() external returns (IntuipayFundsDivider) {
        // Get the deployer's private key from the PRIVATE_KEY environment variable.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get the fee address from the FEE_ADDRESS environment variable.
        address feeAddress = vm.envAddress("FEE_ADDRESS");

        // The deployer's address will be the initial owner.
        address initialOwner = vm.addr(deployerPrivateKey);

        // If FEE_ADDRESS is not set, default to the deployer's address.
        if (feeAddress == address(0)) {
            feeAddress = initialOwner;
        }

        console.log("Deploying IntuipayFundsDivider...");
        console.log("  Initial Owner:", initialOwner);
        console.log("  Fee Address:  ", feeAddress);

        vm.startBroadcast(deployerPrivateKey);

        IntuipayFundsDivider fundsDivider = new IntuipayFundsDivider(
            initialOwner,
            feeAddress
        );

        vm.stopBroadcast();

        console.log("IntuipayFundsDivider deployed to:", address(fundsDivider));

        return fundsDivider;
    }
}
