// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ISparkbloxContract.sol";

contract SimpleLogic is 
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ISparkbloxContract
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant MODULE_TYPE = bytes32("SimpleLogic");
    uint256 private constant VERSION = 2;

    uint public x;
    string public contractURI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint _x) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        
        x = _x;
    }

    function doubleX() public {
        x = x * 2;
    }

    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    function contractVersion() external pure returns (uint8) {
        return uint8(VERSION);
    }

    function setContractURI(string calldata _uri) external {
        contractURI = _uri;
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    override
    {}
}
