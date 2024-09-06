// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

contract Helperconfig is Script {
    error Helperconfig__invalidChainId();

    struct Networkconfig {
        address entrypoint;
        address account;
    }

    address BURNER_WALLET = 0x6ABc3025032F719B5E42f0f97D5C72402E3efB5F;
    address public ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAINID = 300;
    uint256 constant ANVIL_CHAIN_ID = 31337;
    Networkconfig public localNetworkConfig;
    mapping(uint256 chainid => Networkconfig) public ChainIdToNetworkconfig;

    constructor() {
        ChainIdToNetworkconfig[SEPOLIA_CHAIN_ID] = getSepoliaConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (Networkconfig memory) {
        if (chainId == ANVIL_CHAIN_ID) {
            return getOrCreateAnvilconfig();
        } else if (ChainIdToNetworkconfig[chainId].entrypoint != address(0)) {
            return ChainIdToNetworkconfig[chainId];
        } else {
            revert Helperconfig__invalidChainId();
        }
    }

    function getconfig() public returns (Networkconfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaConfig() public view returns (Networkconfig memory) {
        return Networkconfig({entrypoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: BURNER_WALLET});
    }

    function getZksyncConfig() public view returns (Networkconfig memory) {
        return Networkconfig({entrypoint: address(0), account: BURNER_WALLET});
    }

    function getOrCreateAnvilconfig() public returns (Networkconfig memory) {
        if (localNetworkConfig.account != address(0)) {
            return localNetworkConfig;
        }
        console2.log("deploying mocks");
        //deploy a mock entry point contract
        vm.startBroadcast();
        EntryPoint entrypoint = new EntryPoint();
        vm.stopBroadcast();
        //localNetworkConfig = Networkconfig({entrypoint: address(0), account: ANVIL_ADDRESS});
        return localNetworkConfig = Networkconfig({entrypoint: address(entrypoint), account: ANVIL_ADDRESS});
    }
}
