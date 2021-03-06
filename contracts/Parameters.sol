// SPDX-License-Identifier: bsl-1.1

/*
  Copyright 2020 Unit Protocol: Artem Zakharov (az@unit.xyz).
*/
pragma solidity ^0.6.8;

import "./helpers/ERC20Like.sol";
import "./helpers/USDPLib.sol";


/**
 * @title Auth
 * @author Unit Protocol: Artem Zakharov (az@unit.xyz), Alexander Ponomorev (@bcngod)
 * @dev Manages USDP's system access
 **/
contract Auth {

    // address of the the contract with parameters
    Parameters public parameters;

    constructor(address _parameters) public {
        parameters = Parameters(_parameters);
    }

    // ensures tx's sender is a manager
    modifier onlyManager() {
        require(parameters.isManager(msg.sender), "USDP: AUTH_FAILED");
        _;
    }

    // ensures tx's sender is able to modify the Vault
    modifier hasVaultAccess() {
        require(parameters.canModifyVault(msg.sender), "USDP: AUTH_FAILED");
        _;
    }

    // ensures tx's sender is the Vault
    modifier onlyVault() {
        require(msg.sender == parameters.vault(), "USDP: AUTH_FAILED");
        _;
    }
}


/**
 * @title Parameters
 * @author Unit Protocol: Artem Zakharov (az@unit.xyz), Alexander Ponomorev (@bcngod)
 **/
contract Parameters is Auth {

    // determines the minimum percentage of COL token part in collateral, 0 decimals
    mapping(address => uint) public minColPercent;

    // determines the maximum percentage of COL token part in collateral, 0 decimals
    mapping(address => uint) public maxColPercent;

    // map token to stability fee percentage; 3 decimals
    mapping(address => uint) public stabilityFee;

    // map token to initial collateralization ratio; 0 decimals
    mapping(address => uint) public initialCollateralRatio;

    // map token to liquidation ratio; 0 decimals
    mapping(address => uint) public liquidationRatio;

    // map token to liquidation fee percentage, 0 decimals
    mapping(address => uint) public liquidationFee;

    // map token to USDP mint limit
    mapping(address => uint) public tokenDebtLimit;

    // permissions to modify the Vault
    mapping(address => bool) public canModifyVault;

    // managers
    mapping(address => bool) public isManager;

    // enabled oracle types for position spawn
    mapping(USDPLib.Oracle => mapping (address => bool)) public isOracleTypeEnabled;

    // address of the Vault
    address public vault;

    // COL token address
    address public COL;

    /**
     * The address for an Ethereum contract is deterministically computed from the address of its creator (sender)
     * and how many transactions the creator has sent (nonce). The sender and nonce are RLP encoded and then
     * hashed with Keccak-256.
     * Therefore, the Vault address can be pre-computed and passed as an argument before deployment.
    **/
    constructor(address _vault, address _col) public Auth(address(this)) {
        isManager[msg.sender] = true;
        vault = _vault;
        COL = _col;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Grants and revokes manager's status of any address
     * @param who The target address
     * @param permit The permission flag
     **/
    function setManager(address who, bool permit) external onlyManager {
        isManager[who] = permit;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets ability to use token as the main collateral
     * @param token The address of a token
     * @param stabilityFeeValue The percentage of the year stability fee (3 decimals)
     * @param liquidationFeeValue The liquidation fee percentage (0 decimals)
     * @param initialCollateralRatioValue The initial collateralization ratio
     * @param liquidationRatioValue The liquidation ratio
     * @param usdpLimit The USDP token issue limit
     **/
    function setCollateral(
        address token,
        uint stabilityFeeValue,
        uint liquidationFeeValue,
        uint initialCollateralRatioValue,
        uint liquidationRatioValue,
        uint usdpLimit,
        USDPLib.Oracle[] calldata oracles,
        uint minColP,
        uint maxColP
    ) external onlyManager {
        setStabilityFee(token, stabilityFeeValue);
        setLiquidationFee(token, liquidationFeeValue);
        setInitialCollateralRatio(token, initialCollateralRatioValue);
        setLiquidationRatio(token, liquidationRatioValue);
        setTokenDebtLimit(token, usdpLimit);
        for (uint i=0; i < oracles.length; i++) {
            setOracleType(oracles[i], token, true);
        }

        setColPartRange(token, minColP, maxColP);
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets the initial collateral ratio
     * @param token The address of a token
     * @param newValue The collateralization ratio (0 decimals)
     **/
    function setInitialCollateralRatio(address token, uint newValue) public onlyManager {
        require(newValue > 0 && newValue <= 100, "USDP: INCORRECT_COLLATERALIZATION_VALUE");
        initialCollateralRatio[token] = newValue;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets the liquidation ratio
     * @param token The address of a token
     * @param newValue The liquidation ratio (0 decimals)
     **/
    function setLiquidationRatio(address token, uint newValue) public onlyManager {
        require(newValue > 0 && newValue >= initialCollateralRatio[token], "USDP: INCORRECT_COLLATERALIZATION_VALUE");
        liquidationRatio[token] = newValue;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets a permission for an address to modify the Vault
     * @param who The target address
     * @param permit The permission flag
     **/
    function setVaultAccess(address who, bool permit) external onlyManager {
        canModifyVault[who] = permit;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets the percentage of the year stability fee for a particular collateral
     * @param token The token address
     * @param newValue The stability fee percentage (3 decimals)
     **/
    function setStabilityFee(address token, uint newValue) public onlyManager {
        stabilityFee[token] = newValue;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets the percentage of the liquidation fee for a particular collateral
     * @param token The token address
     * @param newValue The liquidation fee percentage (0 decimals)
     **/
    function setLiquidationFee(address token, uint newValue) public onlyManager {
        liquidationFee[token] = newValue;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets the percentage range of the COL token part for specific collateral token
     * @param min The address of collateral token
     * @param min The min percentage (0 decimals)
     * @param max The max percentage (0 decimals)
     **/
    function setColPartRange(address token, uint min, uint max) public onlyManager {
        require(max <= 100 && min <= max, "USDP: WRONG_RANGE");
        minColPercent[token] = min;
        maxColPercent[token] = max;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Enables/disables oracle types
     * @param _type The type of the oracle
     * @param asset The address of the main collateral
     * @param enabled The control flag
     **/
    function setOracleType(USDPLib.Oracle _type, address asset, bool enabled) public onlyManager {
        isOracleTypeEnabled[_type][asset] = enabled;
    }

    /**
     * notice Only manager is able to call this function
     * @dev Sets USDP limit for a specific collateral
     * @param token The token address
     * @param limit The limit number
     **/
    function setTokenDebtLimit(address token, uint limit) public onlyManager {
        tokenDebtLimit[token] = limit;
    }
}
