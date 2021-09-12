//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract Lottery is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Player {
        address payable player;
        address token;
        uint256 amount;
    }

    address payable recipientAddr;
    uint256 constant fee = uint256(5).div(100);
    Player[] public players;

    /**
     * Constructor
     * @param _recipient
     */
    function initialize(address _recipient) public initializer {
        recipientAddr = payable(_recipient);
    }

    function buyTicket() {
        players.push(msg.sender);
    }

    function goLottery() internal{}

    function getBalance() public view return (uint256) {}
}
