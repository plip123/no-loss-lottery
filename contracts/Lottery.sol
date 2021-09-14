//SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "./VRFConsumerBaseUpgradable.sol";
import "hardhat/console.sol";

contract Lottery is Initializable, VRFConsumerBaseUpgradable {
    using SafeERC20 for IERC20;

    struct Player {
        address payable player;
        address token;
        uint256 amount;
    }

    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 internal feeVRF;
    uint256 public randomResult;
    address payable public recipientAddr;
    Player[] public players;

    mapping(address => address) currencies;

    /**
     * Constructor
     * @param _recipient is a fee recipient
     */
    function initialize(address _recipient) public initializer {
        VRFConsumerBaseUpgradable.initialize(
            0xf0d54349aDdcf704F77AE15b96510dEA15cb7952, // VRF Coordinator
            0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token
        );
        recipientAddr = payable(_recipient);
        fee = uint256(5).div(100);
        feeVRF = 0.1 * 10**18; // 0.1 LINK (Varies by network)
        keyHash = 0xAA77729D3466CA35AE8D28B3BBAC7CC36A5031EFDC430821C02BC31A238AF445;
        currencies[
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        ] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        currencies[
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        ] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //USDC
        currencies[
            0xdAC17F958D2ee523a2206206994597C13D831ec7
        ] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        currencies[
            0x0000000000085d4780B73119b644AE5ecd22b376
        ] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        currencies[
            0x4Fabb145d64652a948d72533023f6E7A623C7C53
        ] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // BUSD
        currencies[
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // ETH
    }

    function buyTicket(address token, uint256 amount) public {
        players.push(Player(payable(msg.sender), token, amount));
    }

    function goLottery() internal {
        //return 1;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getRandomNumber() public returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, fee);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;
    }
}
