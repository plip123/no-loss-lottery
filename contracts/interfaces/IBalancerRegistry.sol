//SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IBalancerRegistry {
    function getBestPoolsWithLimit(
        address fromToken,
        address destToken,
        uint256 limit
    ) external view returns (address[] memory pools);
}
