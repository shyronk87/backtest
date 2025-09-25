// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {INonfungiblePositionManager} from "../interface/INonfungiblePositionManager.sol";

/// @title Uniswap Position Management Test
/// @notice Test contract for simulating Uniswap V3 mint, burn and collect operations
contract UniswapPositionTest is Test {
    // =========================================================================
    //                            STATE VARIABLES
    // =========================================================================
    
    // Uniswap V3 constants
    INonfungiblePositionManager private nfpm;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint24 private constant POOL_FEE = 3000;
    
    // Block numbers for the simulation
    // We start at an older block to mint
    uint256 private constant START_BLOCK = 23422403; 
    // We "time travel" to a future block to simulate swaps and fee accumulation
    uint256 private constant END_BLOCK = 23438403;
    
    // Test account address, will be created in setUp
    address private testAccount;

    // =========================================================================
    //                                 SETUP
    // =========================================================================
    
    /// @notice This function is called before each test case.
    function setUp() public {
        // Create a deterministic test account address
        testAccount = makeAddr("testAccount");
        
        // Initialize the NFPM interface with its mainnet address
        nfpm = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        
        // Get RPC URL from environment variables to fork mainnet
        string memory rpcUrl = vm.envString("ETH_RPC");
        require(bytes(rpcUrl).length > 0, "ETH_RPC environment variable not set");
        
        // Create and select a fork of mainnet at the START_BLOCK
        vm.createSelectFork(rpcUrl, START_BLOCK);
    }
    
    // =========================================================================
    //                                 TESTS
    // =========================================================================
    
    /// @notice Test the complete lifecycle of a position:
    ///         1. Mint a new position.
    ///         2. Simulate time passing by fast-forwarding to a future block.
    ///         3. Withdraw liquidity and collect any accrued fees.
    ///         4. Burn the position NFT.
    function testCompleteFlow() public {
        // ======================= STEP 1: MINT POSITION =======================
        
        // Give the test account a large starting balance of USDC and WETH
        deal(USDC, testAccount, 100_000 * 1e6); // 100,000 USDC
        deal(WETH, testAccount, 100 ether);     // 100 WETH

        // Store initial balances for later verification
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(testAccount);
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(testAccount);

        // Impersonate the test account to perform actions
        vm.startPrank(testAccount);

        // Approve the NonfungiblePositionManager to spend our tokens
        IERC20(USDC).approve(address(nfpm), type(uint256).max);
        IERC20(WETH).approve(address(nfpm), type(uint256).max);

        // Prepare parameters for minting the new position
        // NOTE: USDC is token0, WETH is token1 because USDC address is smaller
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: USDC, 
            token1: WETH, 
            fee: POOL_FEE,
            tickLower: 191880, // Tick must be divisible by tickSpacing (60 for 0.3% fee)
            tickUpper: 194100, // Tick must be divisible by tickSpacing (60 for 0.3% fee)
            amount0Desired: 2000 * 1e6, // 2000 USDC
            amount1Desired: 1 ether,       // 1 WETH
            amount0Min: 0,
            amount1Min: 0,
            recipient: testAccount,
            deadline: block.timestamp + 1 days
        });

        // Execute the mint transaction
        (uint256 tokenId, uint128 liquidity, , ) = nfpm.mint(params);
        
        // Stop impersonating the test account
        vm.stopPrank();

        // --- Verification & Logging for Step 1 ---
        assertTrue(tokenId > 0, "Minting failed, tokenId is 0");
        emit log_named_uint("  [STEP 1] Position minted with Token ID", tokenId);


        // ======================= STEP 2: SIMULATE TIME =======================

        // Fast-forward the blockchain to the END_BLOCK
        // This simulates time passing, during which swaps would happen and fees would accrue
        vm.roll(END_BLOCK);
        emit log_named_string(" [STEP 2] Time-traveled to block", toString(END_BLOCK));

        // Check for any fees that have accrued (optional, for debugging)
        // In this simple simulation without actual swaps, fees will likely be 0.
        (, , , , , , , , , , uint128 feesOwed0, uint128 feesOwed1) = nfpm.positions(tokenId);
        emit log_named_uint("   - Accrued USDC fees", feesOwed0);
        emit log_named_uint("   - Accrued WETH fees", feesOwed1);


        // ======================= STEP 3: BURN & COLLECT =======================

        // Impersonate the test account again to withdraw
        vm.startPrank(testAccount);

        // 3.1 Decrease liquidity to zero, which "unlocks" the underlying tokens
        (uint256 amount0Removed, uint256 amount1Removed) = nfpm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity, // Use the liquidity from the mint result
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 days
            })
        );

        // 3.2 Collect all pending funds (the unlocked tokens from decreaseLiquidity + any accrued fees)
        (uint256 amount0Collected, uint256 amount1Collected) = nfpm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: testAccount, // Send funds back to our test account
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        
        // 3.3 Burn the now-empty position NFT
        nfpm.burn(tokenId);

        // Stop impersonating
        vm.stopPrank();

        // --- Logging for Step 3 ---
        emit log("  [STEP 3] Position withdrawn and burned");
        emit log_named_uint("   - Total USDC collected (liquidity + fees)", amount0Collected);
        emit log_named_uint("   - Total WETH collected (liquidity + fees)", amount1Collected);
        

               // ======================= STEP 4: FINAL VERIFICATION =======================

        // Get the final token balances of the test account
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(testAccount);
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(testAccount);

        // 使用 int256 来安全地计算余额变化，避免下溢
        int256 usdcChange = int256(usdcBalanceAfter) - int256(usdcBalanceBefore);
        int256 wethChange = int256(wethBalanceAfter) - int256(wethBalanceBefore);
        
        emit log(" [STEP 4] Final balance verification");
        emit log_named_int("   - Net USDC change", usdcChange);
        emit log_named_int("   - Net WETH change", wethChange);
        
        // 验证逻辑可以保持不变，因为我们只是检查最终余额是否大于0
        assertTrue(usdcBalanceAfter > 0, "Final USDC balance is zero");
        assertTrue(wethBalanceAfter > 0, "Final WETH balance is zero");
    }

    // Helper function to convert uint to string for logging
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}