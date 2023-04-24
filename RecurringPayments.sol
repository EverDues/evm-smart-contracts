// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MultiOwnable.sol";

/**
 * @title Recurring Payments & Subscriptions on EVM
 * @author EverDues
 * @notice This contract implements recurring payments & subscriptions on EVM
 * using ERC20's approval and timelocked proxy of transferFrom() to handle
 * recurring payments that can be cancelled anytime.
 */

contract RecurringPayments is MultiOwnable {
    using SafeERC20 for IERC20;

    event NewSubscription(string, bytes32);

    event SubscriptionCancelled(string);

    event SubscriptionPaid();

    // Mapping to hold information about a user's subscription using subsctiption ID and timestamp of the last payment execution
    mapping(bytes32 => uint32) subscriptions;

    address gas_proxy_address;

    struct PaymentData {
        address customer;
        address token;
        address payee;
        uint32 value;
        uint32 period;
        uint8 networkFee;
        string ipfsHash;
    }

    uint8 constant MAX_NETWORK_FEE = 5; //%

    function setGasProxyAddress(address _gas_proxy_address) external onlyRole(OWNER_ROLE) {
        gas_proxy_address = _gas_proxy_address;
    }

    /**
     * @dev Creates a new subscription for the specified customer.
     * @param _payee The payee address to send subscription payments to.
     * @param _value The cost of the subscription.
     * @param _token The token used to pay for the subscription.
     * @param _ipfsHash The IPFS hash of external data. Period supposed to be added into IPFS hash to save additional gas.
     * @param _sid The unique identifier of the subscription.
     */
    function createSubscription(
        address _payee, 
        uint32 _value, 
        address _token,
        string calldata _ipfsHash, // any additional metadata which user provides (used on backend side to propagate to another chain, embedded into _sid)
        bytes32 _sid // (should be additionally verified off-chain before any action _sid should be calculated from encodeSubscriptionId and match transaction parameters),
    ) external {
        bytes32 sid = keccak256(abi.encodePacked(msg.sender, _sid));
        require(
            subscriptions[sid] == 0,
            "Active subscription already exists."
        );
        subscriptions[sid] = uint32(block.timestamp);
        IERC20(_token).safeTransferFrom(msg.sender, _payee, _value);
        emit NewSubscription(_ipfsHash, _sid);
    }

    /** @dev Cancels an existing subscription for a customer.
     *  @param _payee The payee address to send subscription payments to.
     *  @param _value The cost of the subscription.
     *  @param _token The token used to pay for the subscription.
     *  @param _ipfsHash The IPFS hash of external data. Period supposed to be added into IPFS hash to save additional gas.
     */
    function cancelSubscription(
        address _token,
        address _payee,
        uint32 _value,
        uint32 _period,
        string calldata _ipfsHash
    ) external virtual {
        bytes32 sid = keccak256(abi.encodePacked(msg.sender, encodeSubscriptionId(_token, _payee, _value, _period, _ipfsHash)));
        subscriptions[sid] = 0;
        emit SubscriptionCancelled(_ipfsHash);
    }

    /**
     * @dev Executes a subscription payment for a customer.
     * @param _customer The customer address to send subscription payments from.
     * @param _token The token used to pay for the subscription.
     * @param _payee The payee address to send subscription payments to.
     * @param _value The cost of the subscription.
     * @param _period The subscription period.
     * @param  _payeeFee The transaction gas fee (calculated off-chain depending on gas price, gas token price and value)
     * @param _ipfsHash The IPFS hash of external data. Period supposed to be added into IPFS hash to save additional gas.
     */
    function executePayment(
        address _customer,
        address _token,
        address _payee,
        uint32 _value,
        uint32 _period,
        uint8 _payeeFee,
        string calldata _ipfsHash
    ) private {
        bytes32 sid = keccak256(abi.encodePacked(_customer, encodeSubscriptionId(_token, _payee, _value, _period, _ipfsHash)));
        require(subscriptions[sid] != 0, "Subscription does not exist or has been cancelled.");
        require(_period != 0, "It's lifetime subscription.");
        require(_payeeFee <= MAX_NETWORK_FEE, "network fee cannot be more then MAX_NETWORK_FEE%.");
        uint32 elapsedTime = uint32(block.timestamp) - subscriptions[sid];
        uint32 preprocessingWindow = (_period < 28 days) ? ((_period * 3) / 4) : (_period - 7 days);
        require(elapsedTime > preprocessingWindow, "Subscription has already been paid for this period.");
        uint32 payeeFee = (_value * _payeeFee) / 100;
        if (elapsedTime <= _period) {
            subscriptions[sid] += _period;
        } else {
            subscriptions[sid] = uint32(block.timestamp + _period);
        }
        IERC20(_token).safeTransferFrom(_customer, _payee, _value - payeeFee);
        IERC20(_token).safeTransferFrom(_customer, gas_proxy_address, payeeFee);
        emit SubscriptionPaid();
    }

    /**
     * @dev Executes a batch for subscription payments.
     */
    function batchExecutePayment(
        PaymentData[] calldata payments
    ) external onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < payments.length; i++) {
            executePayment(
                payments[i].customer,
                payments[i].token,
                payments[i].payee,
                payments[i].value,
                payments[i].period,
                payments[i].networkFee,
                payments[i].ipfsHash
            );
        }
    }
    /**
     * @dev Generates a unique subscription ID based on the given parameters.
     * @param _token The token address.
     * @param _payee The payee address.
     * @param _value The subscription cost.
     * @param _period The subscription period.
     * @param _ipfsHash The IPFS hash of external metadata. Period supposed to be added into IPFS hash to save additional gas.
     * @return A unique subscription ID based on the given parameters.
     */
    function encodeSubscriptionId(
        address _token,             // ERC20 token address
        address _payee,             // address of the payee
        uint32  _value,             // subscription value
        uint32  _period,            // subscription period
        string calldata _ipfsHash   // The IPFS hash of external metadata
    ) public pure returns (bytes32) {
        // Create a unique ID for the subscription by hashing the inputs using the keccak256 hash function
        // This ID will be used to identify the subscription in the subscriptions mapping
        return keccak256(abi.encodePacked(_token, _payee, _value, _period, _ipfsHash));
    }

    function getSubscriptionTimestamp(address _customer, bytes32 _sid) external view returns (uint32 timestamp) {
        return subscriptions[keccak256(abi.encodePacked(_customer, _sid))];
    }
}
