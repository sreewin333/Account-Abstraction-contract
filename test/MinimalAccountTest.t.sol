// SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Helperconfig} from "../script/HelperConfig.s.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation} from "../script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccountTest is Test {
    /**
     * send transaction to alt-mempool nodes =>ethereum node(entry point contact)=> our contract(MinimalAccount) => destination contract
     */
    using MessageHashUtils for bytes32;

    Helperconfig config;
    DeployMinimal deployer;
    MinimalAccount minimalAccount;
    SendPackedUserOp sendPackedUserOp;
    uint256 public mintAmount = 1e18;
    ERC20Mock public erc20;
    address user = makeAddr("user");
    address accountAddress;
    address entryPointAddress;
    Helperconfig.Networkconfig configuration;

    function setUp() external {
        deployer = new DeployMinimal();
        (minimalAccount, config) = deployer.deployMinimalAccount();
        configuration = config.getconfig();
        accountAddress = configuration.account;
        entryPointAddress = configuration.entrypoint;
        sendPackedUserOp = new SendPackedUserOp();
        erc20 = new ERC20Mock();
        vm.deal(address(minimalAccount), 10e18);
    }

    function testowner() public view {
        address expectedAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address actualAddress = minimalAccount.owner();
        assertEq(expectedAddress, actualAddress);
    }

    function testOwnerCanExecuteCommands() public {
        //arrange
        assertEq(erc20.balanceOf(address(minimalAccount)), 0);
        address destination = address(erc20);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);
        // or we can do this => abi.encodeWithSignature("mint(address,uint256)", minimalAccount, mintAmount);

        //act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(destination, value, functionData);

        //assert

        assertEq(erc20.balanceOf(address(minimalAccount)), mintAmount);
    }

    function testOnlyOwnerOrEntryPointCanExecute() public {
        //arrange
        assertEq(erc20.balanceOf(address(minimalAccount)), 0);
        address destination = address(erc20);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);
        // or we can do this => abi.encodeWithSignature("mint(address,uint256)", minimalAccount, mintAmount);

        //act and assert
        vm.prank(user);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotTheOwnerOrEntryPoint.selector);
        minimalAccount.execute(destination, value, functionData);
    }

    function testRecoverSignedOp() public view {
        //Arrange
        assertEq(erc20.balanceOf(address(minimalAccount)), 0);
        address destination = address(erc20);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);

        bytes memory executeCalldata =
            abi.encodeWithSelector(MinimalAccount.execute.selector, destination, value, functionData);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCalldata, configuration, address(minimalAccount));
        bytes32 userOperationHash = IEntryPoint(entryPointAddress).getUserOpHash(packedUserOp);
        //Act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);
        //Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    function testValidationOfUserOps() public {
        //Arrange
        address destination = address(erc20);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);

        bytes memory executeCalldata =
            abi.encodeWithSelector(MinimalAccount.execute.selector, destination, value, functionData);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCalldata, configuration, address(minimalAccount));
        bytes32 userOperationHash = IEntryPoint(entryPointAddress).getUserOpHash(packedUserOp);
        //Act
        vm.prank(entryPointAddress);
        uint256 missingAccountFunds = 1e18;
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testEntryPointcanExecutecommands() public {
        //Arrange
        address destination = address(erc20);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), mintAmount);

        bytes memory executeCalldata =
            abi.encodeWithSelector(MinimalAccount.execute.selector, destination, value, functionData);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCalldata, configuration, address(minimalAccount));
        // bytes32 userOperationHash = IEntryPoint(entryPointAddress).getUserOpHash(packedUserOp);
        PackedUserOperation[] memory Ops = new PackedUserOperation[](1);
        Ops[0] = packedUserOp;
        //Act
        vm.prank(user);
        IEntryPoint(entryPointAddress).handleOps(Ops, payable(user));

        //assert
        assertEq(erc20.balanceOf(address(minimalAccount)), mintAmount);
    }
}
