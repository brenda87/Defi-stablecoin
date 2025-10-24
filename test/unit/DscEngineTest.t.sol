// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";

contract DscEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_MINTED = 10 ether;
    uint256 public amountToMint = 100 ether;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, AMOUNT_COLLATERAL);
    }

    /**
     * Constructor tests
     */
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenAddressesLengthNotEqualPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /**
     * Price feed tests
     */
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000e8 / 1e8
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /**
     * Deposit collateral tests
     */
    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom badToken = new MockFailedTransferFrom(owner);
        tokenAddresses = [address(badToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        // DSCEngine receives the third parameter as dscAddress, not the tokenAddress used as collateral.
        vm.prank(owner);
        DSCEngine badEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        badToken.mint(user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        ERC20Mock(address(badToken)).approve(address(badEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        badEngine.depositCollateral(address(badToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        vm.startPrank(user);
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /*
     * DepositCollateralAndMintDsc tests
     */

    

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndMintDsc() public depositedCollateralAndMintedDsc{
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, AMOUNT_DSC_MINTED);
    }

    /**
     * Mint DSC tests
     */
    function testRevertsIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(user);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        // deploy dscengine as user
        vm.prank(user);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        // Transfer ownership to the mock DSCEngine
        vm.prank(user);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral{
        vm.prank(user);
        engine.mintDSC(amountToMint);
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }
}
