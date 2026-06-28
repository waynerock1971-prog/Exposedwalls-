// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos) external view
        returns (int56[] memory tickCumulatives,
                 uint160[] memory secondsPerLiquidityCumulativeX128s);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt,
        uint256 updatedAt, uint80 answeredInRound);
}

contract EWBGorillaOracle {
    address public ewbPool;
    address public constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint32  public twapWindow         = 30 days;
    uint256 public manualFloorETH;
    bool    public useManualFloor;
    uint256 public manualFloorSetAt;
    uint256 public manualFloorMaxAge = 7 days;
    uint256 public chainlinkMaxAge    = 3600;

    address public immutable owner;

    event PoolUpdated(address indexed pool);
    event ManualFloorSet(uint256 floorETH, uint256 timestamp);
    event ManualFloorDisabled(uint256 timestamp);
    event TWAPWindowUpdated(uint32 window);
    event ChainlinkMaxAgeUpdated(uint256 maxAge);
    event ManualFloorMaxAgeUpdated(uint256 maxAge);

    constructor(address _ewbPool, address _owner) {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
        ewbPool = _ewbPool;
    }

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    function getETHUSDPrice() external view returns (uint256) {
        (, int256 price, , uint256 updatedAt,) =
            AggregatorV3Interface(ETH_USD_FEED).latestRoundData();
        require(price > 0, "Invalid Chainlink price");
        require(block.timestamp - updatedAt < chainlinkMaxAge, "Stale Chainlink feed");
        return uint256(price) * 1e10;
    }

    function getFloorPriceETH() external view returns (uint256) {
        if (useManualFloor) {
            require(block.timestamp - manualFloorSetAt <= manualFloorMaxAge, "Floor stale");
            return manualFloorETH;
        }
        return _getTWAPPrice();
    }

    function setManualFloor(uint256 _floorETH) external onlyOwner {
        require(_floorETH > 0, "Floor must be > 0");
        manualFloorETH   = _floorETH;
        manualFloorSetAt = block.timestamp;
        useManualFloor   = true;
        emit ManualFloorSet(_floorETH, block.timestamp);
    }

    function setManualFloorMaxAge(uint256 _maxAge) external onlyOwner {
        manualFloorMaxAge = _maxAge;
        emit ManualFloorMaxAgeUpdated(_maxAge);
    }

    function disableManualFloor() external onlyOwner {
        useManualFloor = false;
        emit ManualFloorDisabled(block.timestamp);
    }

    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool");
        ewbPool = _pool;
        emit PoolUpdated(_pool);
    }

    function _getTWAPPrice() internal view returns (uint256) {
        require(ewbPool != address(0), "Pool not set");
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(ewbPool).observe(secondsAgos);
        int56  tickDiff = tickCumulatives[1] - tickCumulatives[0];
        int24  avgTick  = int24(tickDiff / int56(uint56(twapWindow)));
        return _tickToPrice(avgTick);
    }

    function _tickToPrice(int24 tick) internal pure returns (uint256) {
        uint256 absTick = tick < 0
            ? uint256(int256(-int256(tick)))
            : uint256(int256(tick));
        require(absTick <= 887272, "Tick out of range");
        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2     != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4     != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8     != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (tick > 0) ratio = type(uint256).max / ratio;
        uint256 sqrtPriceX96 = ratio >> 32;
        uint256 lo = sqrtPriceX96 & type(uint128).max;
        uint256 hi = sqrtPriceX96 >> 128;
        require(hi == 0, "sqrtPrice overflow");
        uint256 priceX192 = lo * lo;
        return (priceX192 * 1e18) >> 192;
    }
}
