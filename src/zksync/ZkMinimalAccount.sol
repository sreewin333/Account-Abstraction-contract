// SPDX-License-Identifier:MIT
import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Utils} from "foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

pragma solidity 0.8.24;

contract ZkMinimalAccount is IAccount, Ownable {
    constructor() Ownable(msg.sender) {}

    function recieve() external payable {}

    //////////////
    ////errors////
    //////////////
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__ExecutionFromOutsideFailed();

    using MemoryTransactionHelper for Transaction;
    ////////////////
    ///modifiers///
    //////////////

    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }

    /**
     * Lifecycle of a type 113 (0x71) transaction
     * msg.sender is the bootloader system contract
     *
     * Phase 1 Validation
     * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
     * 2. The zkSync API client checks to see the the nonce is unique by querying the NonceHolder system contract
     * 3. The zkSync API client calls validateTransaction, which MUST update the nonce
     * 4. The zkSync API client checks the nonce is updated
     * 5. The zkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction
     * 6. The zkSync API client verifies that the bootloader gets paid
     *
     * Phase 2 Execution
     * 7. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are the same)
     * 8. The main node calls executeTransaction
     * 9. If a paymaster was used, the postTransaction is called
     */

    // --system-mode=true
    function validateTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoader
        returns (bytes4 magic)
    {
        magic = _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic == bytes4(0)) {
            revert ZkMinimalAccount__ExecutionFromOutsideFailed();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) revert ZkMinimalAccount__FailedToPay();
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}
    ///////////////////////
    //internal functions//
    /////////////////////

    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, _transaction.nonce)
        );
        // check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) revert ZkMinimalAccount__NotEnoughBalance();

        //check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isOwner = signer == owner();
        if (isOwner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
            /**
             * (this is checking whether if we are trying to deploy a contract on zksync if it is,then we need to interact with the system contract "DEPLOYER_SYSTEM_CONTRACT")
             * zksync have these contracts deployed on them to check for
             * all other things like, if we want to deploy a contract on zksync,a contract deployed on
             * the zksync called deployer contract handles that operation, so we need to interact with that contract,
             * these contracts that handles these types of things are called "system contracts"(there are lots of them like
             * "NONCE_HOLDER_SYSTEM_CONTRACT" in this contract which increments the nonce if the transaction(zksync provides
             * us to increment the nonce of the transaction on our own)).in order to call them we have to go through
             * these special calling and we have to make (is-system=true or(--system-mode=true)dont know the correct one yet)
             *  this in the foundry.toml to interact with them.
             *
             */
        } else {
            bool succes;
            assembly {
                succes := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!succes) revert ZkMinimalAccount__ExecutionFailed();
        }
    }
}
