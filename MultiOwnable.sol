// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract MultiOwnable is AccessControlEnumerable  {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OWNER_ROLE, msg.sender);
    }

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "MultiOwnable: sender must be an owner");
        _;
    }

    function addOwner(address newOwner) public onlyOwner {
        grantRole(OWNER_ROLE, newOwner);
    }

    function removeOwner(address owner) public onlyOwner {
        require(getRoleMemberCount(OWNER_ROLE) > 1, "MultiOwnable: cannot remove last owner");
        revokeRole(OWNER_ROLE, owner);
    }
}
