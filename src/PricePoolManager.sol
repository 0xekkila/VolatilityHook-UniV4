// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {PoolManager} from "@v4-core/PoolManager.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "@v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@v4-core/types/Currency.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@v4-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {SafeCast} from "@v4-core/libraries/SafeCast.sol";
import {HookMiner} from "contracts/utils/HookMiner.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";

import {OracleBasedFeeHook} from "src/OracleBasedFeeHook.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title PricePoolManager
 * @author 0xEkkila
 * @notice This contract is used to set the price of a two asset pool by managing the liquidity and creating pool at set price
 */
contract PricePoolManager {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCast for uint128;

    IPoolManager public immutable poolManager;
    PoolModifyLiquidityTest public immutable lpRouter;
    IChainlinkOracle public immutable oracle;

    IHooks public hook;

    PoolKey public poolKey;
    address public sETH;
    address public sUSDC;

    address public token0;
    address public token1;

    int24 public constant MIN_TICK = -887220;
    int24 public constant MAX_TICK = 887220;
    uint24 public constant SWAP_FEE = 0x800000;
    int24 public constant TICK_SPACING = 60;

    address public immutable create2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address public immutable calcLib = 0xDCbc7a9B253c89d4257B34Fa52F69d82D09AbdCa;

    constructor(
        address _poolManager,
        address _lpRouter,
        address _hook,
        address _oracle,
        address _sETH,
        address _sUSDC
    ) {
        poolManager = PoolManager(_poolManager);
        lpRouter = PoolModifyLiquidityTest(_lpRouter);
        hook = IHooks(_hook);
        oracle = IChainlinkOracle(_oracle);

        sETH = _sETH;
        sUSDC = _sUSDC;

        token0 = uint160(sUSDC) < uint160(sETH) ? sUSDC : sETH;
        token1 = uint160(sUSDC) < uint160(sETH) ? sETH : sUSDC;
    }

    function getCurrentPoolPrice() external returns (uint256) {
        return uint256(oracle.latestAnswer());
    }

    function getSqrtPriceX96(uint256 price) external pure returns (uint160) {
        // Convert price to Q64.96 format
        uint256 priceQ64x96 = price << 96;

        // Calculate square root using Babylonian method
        uint256 z = (priceQ64x96 + 1) >> 1;
        uint256 y = priceQ64x96;

        for (uint256 i = 0; i < 8; i++) {
            z = (z + y / z) >> 1;
        }

        // Ensure the result fits in uint160
        require(z <= type(uint160).max, "Price out of range");

        return uint160(z);
    }

    function initiatePool(int256 amount) external returns (PoolKey memory newPoolKey) {
        // Deploy Hook
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);

        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(OracleBasedFeeHook).creationCode,
            abi.encode(IPoolManager(poolManager), address(calcLib))
        );

        OracleBasedFeeHook newHook = new OracleBasedFeeHook{salt: salt}(IPoolManager(poolManager), address(calcLib));

        // Initialize Pool
        newPoolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: SWAP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(newHook)
        });

        IPoolManager.ModifyLiquidityParams memory param =
            IPoolManager.ModifyLiquidityParams(MIN_TICK, MAX_TICK, amount, 0);

        poolManager.initialize(newPoolKey, this.getSqrtPriceX96(this.getCurrentPoolPrice()), new bytes(0));
        lpRouter.modifyLiquidity(newPoolKey, param, new bytes(0));

        // Set Current Pool Key
        poolKey = newPoolKey;
    }

    function recreatePoolWithCurrentPrice() external {
        // Get Pool Current SqrtX96 Price
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Get Pool Balance of sETH and sUSDC
        uint256 token0Amount = ERC20(token0).balanceOf(address(poolManager));
        uint256 token1Amount = ERC20(token1).balanceOf(address(poolManager));

        // Get Current Liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            token0Amount,
            token1Amount
        );

        // Withdraw Liquidity from Old Pool
        IPoolManager.ModifyLiquidityParams memory param =
            IPoolManager.ModifyLiquidityParams(MIN_TICK, MAX_TICK, -(liquidity.toInt256()), 0);

        lpRouter.modifyLiquidity(poolKey, param, new bytes(0));

        // Initialize Pool
        PoolKey memory newPoolKey = this.initiatePool(liquidity.toInt256());

        // Set Current Pool Key
        poolKey = newPoolKey;
    }
}
