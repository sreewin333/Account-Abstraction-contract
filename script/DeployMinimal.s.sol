// SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Helperconfig} from "./HelperConfig.s.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";

contract DeployMinimal is Script {
    function run() external {}

    function deployMinimalAccount() public returns (MinimalAccount, Helperconfig) {
        Helperconfig helperconfig = new Helperconfig();
        Helperconfig.Networkconfig memory config = helperconfig.getconfig();

        vm.startBroadcast(config.account);
        MinimalAccount minimalAccount = new MinimalAccount(config.entrypoint);
        minimalAccount.transferOwnership(config.account);
        vm.stopBroadcast();
        return (minimalAccount, helperconfig);
    }
}
