// SPDX-License-Identifier:MIt
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMinimalAccount} from "../src/zksync/ZkMinimalAccount.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {BOOTLOADER_FORMAL_ADDRESS} from "foundry-era-contracts/src/system-contracts/contracts/Constants.sol";

contract zkMinimalAccount is Test {
    ZkMinimalAccount public minimalAccount;
    ERC20Mock public token;
    address public ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    bytes32 empty_bytes32 = bytes32(0);

    function setUp() external {
        minimalAccount = new ZkMinimalAccount();
        minimalAccount.transferOwnership(ANVIL_ADDRESS);
        token = new ERC20Mock();
        vm.deal(address(minimalAccount), 1e18);
    }

    function testExecute() public {
        //Arrange
        address from = minimalAccount.owner();
        address destionation = address(token);
        uint256 txType = 113;
        uint256 value = 0;
        uint256 mintAmount = 1e18;
        bytes memory data = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);

        Transaction memory _transaction = _transactionHelper(from, destionation, txType, value, data);
        //Act
        vm.prank(minimalAccount.owner());
        minimalAccount.executeTransaction(empty_bytes32, empty_bytes32, _transaction);
        //Assert

        assertEq(token.balanceOf(address(minimalAccount)), mintAmount);
    }

    function testZkValidateTransaction() public {
        //Arrange
        address from = minimalAccount.owner();
        address destionation = address(token);
        uint256 txType = 113;
        uint256 value = 0;
        uint256 mintAmount = 1e18;
        bytes memory data = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);
        Transaction memory _transaction = _transactionHelper(from, destionation, txType, value, data);
        _transaction = _signTransaction(_transaction);
        //Act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        bytes4 maigc = minimalAccount.validateTransaction(empty_bytes32, empty_bytes32, _transaction);
        //Assert
        assertEq(maigc, ACCOUNT_VALIDATION_SUCCESS_MAGIC);

        //(for this test we have to add --system-mode=true in the command line after --zksync).
    }

    ///helper contracts
    function _transactionHelper(address from, address to, uint256 _txType, uint256 value, bytes memory data)
        internal
        view
        returns (Transaction memory)
    {
        uint256 nonce = vm.getNonce(address(minimalAccount));
        bytes32[] memory factorydeps = new bytes32[](0);
        return Transaction({
            txType: _txType,
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit: 16777216,
            gasPerPubdataByteLimit: 16777216,
            maxFeePerGas: 16777216,
            maxPriorityFeePerGas: 16777216,
            paymaster: 0,
            nonce: nonce,
            value: value,
            reserved: [uint256(0), uint256(0), uint256(0), uint256(0)],
            data: data,
            signature: hex"",
            factoryDeps: factorydeps,
            paymasterInput: hex"",
            reservedDynamic: hex""
        });
    }

    function _signTransaction(Transaction memory _transaction) internal view returns (Transaction memory) {
        bytes32 digest = MemoryTransactionHelper.encodeHash(_transaction);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80, digest);
        _transaction.signature = abi.encodePacked(r, s, v);
        return _transaction;
    }
}
