// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

/// @title Configuration for Uniswap Mint Simulation
/// @notice Centralized configuration for the Uniswap V3 mint operation simulation
library Config {
    // Block numbers for the simulation
    uint256 public constant MINT_BLOCK = 23422403;
    uint256 public constant BURN_COLLECT_BLOCK = 23438403;
    
    // Uniswap V3 Factory address on Ethereum Mainnet
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    
    // Nonfungible Position Manager address on Ethereum Mainnet
    address public constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    
    // WETH token address on Ethereum Mainnet
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // USDC token address on Ethereum Mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Pool fee tier (0.3% = 3000)
    uint24 public constant POOL_FEE = 3000;
    
    // Test account information
    address public constant TEST_ACCOUNT = 0x5f7005bC5fBf831C60d0d2add0AE37ac9Cf11571;
    
    // Amounts for liquidity provision
    uint256 public constant AMOUNT0 = 1 ether;  // 1 WETH
    uint256 public constant AMOUNT1 = 2000 * 1e6;  // 2000 USDC
    
    // Get RPC URL from environment variables
    function getRpcUrl() internal view returns (string memory) {
        return Vm(address(uint160(uint256(keccak256('hevm cheat code'))))).envString("ETH_RPC");
    }
}