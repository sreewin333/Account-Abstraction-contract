// SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    IEntryPoint immutable i_entryPoint;

    ///////////
    //errors///
    ///////////
    error MinimalAccount__TransferFailed();
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotTheOwnerOrEntryPoint();
    error MinimalAccount__destinationCallFailed(bytes data);

    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }
    ///////////////
    ///modifiers///
    ///////////////

    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != owner() && msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotTheOwnerOrEntryPoint();
        }
        _;
    }

    //receive function to accept payment in the contract for this function _payPreFund

    receive() external payable {}

    // this is the function that is needed in an account abstraction contract.(this is the function the entrypoint contract is going to call)
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPreFund(missingAccountFunds);
    }

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        //the  MessageHashUtils.toEthSignedMessageHash(userOpHash) is done because it need the formation standard of the-
        //eip-191,only then we can recover the signer using ECDSA.recover
        // it need to return as uint256 too,(SIG_VALIDATION_FAILED=1 and  SIG_VALIDATION_SUCCESS=0)
        bytes32 ethSignedmessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedmessageHash, userOp.signature);
        if (signer != owner()) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPreFund(uint256 amount) internal {
        if (amount != 0) {
            (bool success,) = payable(msg.sender).call{value: amount, gas: type(uint256).max}("");
            if (!success) revert MinimalAccount__TransferFailed();
        }
    }
    ////////////////////////
    //external functions///
    //////////////////////

    //this is the function that execute what we need(literally anything we want to call from this contract(eg:-mint an erc20))
    function execute(address destination, uint256 value, bytes calldata functionData)
        external
        requireFromEntryPointOrOwner
    {
        (bool success, bytes memory result) = destination.call{value: value}(functionData);
        if (!success) revert MinimalAccount__destinationCallFailed(result);
    }

    ////////////
    //Getters///
    ////////////

    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}
