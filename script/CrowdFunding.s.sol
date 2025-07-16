// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {CrowdFunding} from "../src/CrowdFunding.sol";

contract CrowdFundingScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Set platform address (can be changed later by owner)
        address platformAddress = vm.envOr("PLATFORM_ADDRESS", deployer);
        
        console.log("Deploying CrowdFunding contract...");
        console.log("Deployer:", deployer);
        console.log("Platform Address:", platformAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        CrowdFunding crowdFunding = new CrowdFunding(deployer, platformAddress);
        
        vm.stopBroadcast();
        
        console.log("CrowdFunding deployed to:", address(crowdFunding));
        console.log("Owner:", crowdFunding.owner());
        console.log("Platform Address:", crowdFunding.platformAddress());
        // console.log("Platform Fee Percentage:", crowdFunding.platformFeePercentage(), "(", crowdFunding.platformFeePercentage() / 100, "%)");
    }
}
