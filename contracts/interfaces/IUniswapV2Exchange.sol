//SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Exchange {
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

library UniswapV2ExchangeLib {
    using SafeMath for uint256;

    function getReturn(
        IUniswapV2Exchange exchange,
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amountIn
    ) internal view returns (uint256) {
        uint256 reserveIn = fromToken.balanceOf(address(exchange));
        uint256 reserveOut = destToken.balanceOf(address(exchange));

        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        return (denominator == 0) ? 0 : numerator.div(denominator);
    }
}
