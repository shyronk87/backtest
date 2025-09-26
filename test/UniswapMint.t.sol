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
    uint256 private constant START_BLOCK = 20030246; 
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

        // Store and log initial balances for later verification
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(testAccount);
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(testAccount);
        
        emit log("--- Balances Before Mint ---");
        emit log_named_decimal_uint("Initial USDC Balance", usdcBalanceBefore, 6);
        emit log_named_decimal_uint("Initial WETH Balance", wethBalanceBefore, 18);
        emit log("-----------------------------");


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
            tickUpper: 194220, // Tick must be divisible by tickSpacing (60 for 0.3% fee)
            amount0Desired: 2000 * 1e6, // 2000 USDC
            amount1Desired: 1 ether,       // 1 WETH
            amount0Min: 0,
            amount1Min: 0,
            recipient: testAccount,
            deadline: block.timestamp + 1 days
        });

        // Execute the mint transaction
        (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) = nfpm.mint(params);
        
        // Stop impersonating the test account
        vm.stopPrank();

        // --- Verification & Logging for Step 1 ---
        assertTrue(tokenId > 0, "Minting failed, tokenId is 0");
        
        // Get and log balances immediately after the mint transaction
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(testAccount);
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(testAccount);

        emit log_named_uint("[STEP 1] Position minted with Token ID", tokenId);
        emit log_named_uint("   - Liquidity Created", liquidity);
        emit log("--- Amounts Actually Used in Mint ---");
        emit log_named_decimal_uint("USDC Used (amount0)", amount0Used, 6);
        emit log_named_decimal_uint("WETH Used (amount1)", amount1Used, 18);
        emit log("------------------------------------");
        emit log("--- Balances After Mint ---");
        emit log_named_decimal_uint("Final USDC Balance", usdcBalanceAfter, 6);
        emit log_named_decimal_uint("Final WETH Balance", wethBalanceAfter, 18);
        emit log("----------------------------");

        // ======================= STEP 2: SIMULATE TIME =======================

        // Fast-forward the blockchain to the END_BLOCK
        // This simulates time passing, during which swaps would happen and fees would accrue
        vm.roll(END_BLOCK);
      
        // Check for any fees that have accrued (optional, for debugging)
        // In this simple simulation without actual swaps, fees will likely be 0.
        (, , , , , , , , , , uint128 feesOwed0, uint128 feesOwed1) = nfpm.positions(tokenId);
        emit log_named_uint("   - Accrued USDC fees", feesOwed0);
        emit log_named_uint("   - Accrued WETH fees", feesOwed1);


     // ======================= STEP 3: BURN & COLLECT =======================

        emit log(" "); // Add a blank line for readability
        emit log("--- Balances Before Withdraw ---");
        uint256 usdcBalanceBeforeWithdraw = IERC20(USDC).balanceOf(testAccount);
        uint256 wethBalanceBeforeWithdraw = IERC20(WETH).balanceOf(testAccount);
        emit log_named_decimal_uint("USDC Balance", usdcBalanceBeforeWithdraw, 6);
        emit log_named_decimal_uint("WETH Balance", wethBalanceBeforeWithdraw, 18);
        emit log("-------------------------------");
        
        // Impersonate the test account again to withdraw
        vm.startPrank(testAccount);

        // --- 3.1 Decrease liquidity to zero ---
        // This action "unlocks" the underlying tokens from the position,
        // but DOES NOT transfer them to the wallet yet. They are now pending collection.
        (uint256 amount0Removed, uint256 amount1Removed) = nfpm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity, // Use the liquidity from the mint result
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 days
            })
        );
        
        emit log(" [STEP 3.1] Liquidity Decreased to Zero");
        emit log("--- Amounts Unlocked from Position ---");
        emit log_named_decimal_uint("USDC Unlocked (amount0)", amount0Removed, 6);
        emit log_named_decimal_uint("WETH Unlocked (amount1)", amount1Removed, 18);
        emit log("-------------------------------------");

        // Let's check the balance right after decreasing liquidity.
        // It SHOULD NOT have changed yet!
        emit log("--- Balances After DecreaseLiquidity (Before Collect) ---");
        emit log_named_decimal_uint("USDC Balance", IERC20(USDC).balanceOf(testAccount), 6);
        emit log_named_decimal_uint("WETH Balance", IERC20(WETH).balanceOf(testAccount), 18);
        emit log_string("   (Note: Balances are unchanged, as expected)");
        emit log("------------------------------------------------------");


        // --- 3.2 Collect all pending funds ---
        // This action transfers the unlocked tokens AND any accrued fees to the recipient's wallet.
        (uint256 amount0Collected, uint256 amount1Collected) = nfpm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: testAccount, // Send funds back to our test account
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        
        emit log(" [STEP 3.2] Funds Collected");
        emit log("--- Amounts Transferred to Wallet ---");
        emit log_named_decimal_uint("USDC Collected (liquidity + fees)", amount0Collected, 6);
        emit log_named_decimal_uint("WETH Collected (liquidity + fees)", amount1Collected, 18);
        emit log("------------------------------------");

        
        // --- 3.3 Burn the now-empty position NFT ---
        nfpm.burn(tokenId);
        emit log("[STEP 3.3] Position NFT Burned");

        // Stop impersonating
        vm.stopPrank();


       
        // ======================= STEP 4: FINAL VERIFICATION =======================
        
        emit log(" "); // Add a blank line
        emit log("--- Balances After Full Withdraw & Collect ---");
        usdcBalanceAfter = IERC20(USDC).balanceOf(testAccount);
        wethBalanceAfter = IERC20(WETH).balanceOf(testAccount);
        emit log_named_decimal_uint("Final USDC Balance", usdcBalanceAfter, 6);
        emit log_named_decimal_uint("Final WETH Balance", wethBalanceAfter, 18);
        emit log("---------------------------------------------");
        
        // Calculate the net change over the entire lifecycle
        int256 usdcChange = int256(usdcBalanceAfter) - int256(usdcBalanceBefore);
        int256 wethChange = int256(wethBalanceAfter) - int256(wethBalanceBefore);
        
        emit log("[STEP 4] Final balance verification");
        emit log_named_decimal_int("   - Net USDC change (wei)", usdcChange, 0); // Log wei change for precision
        emit log_named_decimal_int("   - Net WETH change (wei)", wethChange, 0); // Log wei change for precision
        
        // Final assertions
        assertTrue(usdcBalanceAfter > 0, "Final USDC balance is zero");
        assertTrue(wethBalanceAfter > 0, "Final WETH balance is zero");
    }

}