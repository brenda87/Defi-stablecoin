// SPDX-License-Identifier: MIT
//what are our invariants?
//1. The total supply of DSC should never exceed the total value of collateral
//2. Getter view functions should never revert
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../fuzz/Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
        
        //targetContract(address(engine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the total value of collateral in the protocol
        // compare it to the total supply of DSC
        uint256 totalSupply  = dsc.totalSupply();
        uint256 totalwethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalwbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethvalue = engine.getUsdValue(weth, totalwethDeposited);
        uint256 wbtcvalue = engine.getUsdValue(wbtc, totalwbtcDeposited);

        console.log("weth value: ", wethvalue);
        console.log("wbtc value: ", wbtcvalue);
        console.log("total supply: ", totalSupply);
        console.log("times mint called: ", handler.timesMintDscCalled());

        assert(wethvalue + wbtcvalue >= totalSupply);
    }

    function invariant_getterFunctionsDontRevert() public view {
        // we can call all the getter functions in the engine without it reverting
        engine.getCollateralTokens();
        engine.getCollateralBalanceOfUser(address(1), weth);
        engine.getAccountInformation(address(1));
        engine.getCollateralBalanceOfUser(address(1), wbtc);
        engine.getUsdValue(weth, 100);
        engine.getUsdValue(wbtc, 100);
    }
}