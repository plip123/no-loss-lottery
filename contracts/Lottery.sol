//SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./VRFConsumerBaseUpgradable.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IUniswapV2Router.sol";
import "hardhat/console.sol";

contract Lottery is
    VRFConsumerBaseUpgradable,
    Initializable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    enum LotteryStatus {
        OPEN,
        STARTED,
        CLOSE
    }

    struct Player {
        uint256 id;
        address payable player;
        address token;
        uint256 number;
    }

    IUniswapV2Router internal constant swapper =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    LotteryStatus public lotteryStatus;
    uint256 public lotteryId;
    uint256 internal fee;
    uint256 public ticketCost;
    address payable public recipientAddr;
    address internal poolAddress;
    Player[] public players;

    bytes32 internal keyHash;
    uint256 internal feeVRF;
    uint256 public winnerNumber;
    address private vrfCoordinator;

    mapping(bytes32 => uint256) lotteryRecord;
    mapping(address => address) currencies;
    mapping(address => uint256) playerId;

    event NewPlayer(address player);

    /**
     * Constructor
     * @param _recipient is a fee recipient
     */
    function initialize(
        address _recipient,
        address _vrfCoordinator,
        uint256 _ticketCost
    ) public initializer {
        vrfCoordinator = _vrfCoordinator;
        VRFConsumerBaseUpgradable.initializeVRF(
            vrfCoordinator, // VRF Coordinator
            0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token
        );

        recipientAddr = payable(_recipient);
        fee = uint256(5);
        ticketCost = _ticketCost;

        feeVRF = 2 * 10**18; // 2 LINK (Varies by network)
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
        // currencies[0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // ETH
    }

    function buyTicket(address tokenAddr, uint256 _number) public {
        require(lotteryStatus == LotteryStatus.OPEN, "The lottery is closed");
        require(msg.sender != address(0), "Invalid user");
        require(tokenAddr == currencies[tokenAddr], "Currency is desactived");
        require(
            IERC20(tokenAddr).balanceOf(msg.sender) >= ticketCost,
            "Balance not enough"
        );
        require(
            playerId[msg.sender] != lotteryId,
            "You are participating in this lottery"
        );
        require(_number > 0, "Invalid selected number");

        IERC20(tokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            ticketCost
        );

        players.push(
            Player(lotteryId, payable(msg.sender), tokenAddr, _number)
        );
        playerId[msg.sender] = players.length - 1;
    }

    function openLottery() public onlyOwner {
        require(lotteryStatus == LotteryStatus.CLOSE, "Lottery in progress");
        lotteryId = 1;
        lotteryStatus = LotteryStatus.OPEN;
    }

    function startLottery(address _tokenAddr, address _poolAddress)
        public
        onlyOwner
    {
        require(lotteryStatus == LotteryStatus.OPEN, "Lottery is not open");
        require(players.length > 0, "Not enough players");
        require(_tokenAddr == currencies[_tokenAddr], "Currency is desactived");
        poolAddress = _poolAddress;
        lotteryStatus = LotteryStatus.STARTED;
        address[] memory path = new address[](2);
        path[1] = _tokenAddr;

        for (uint256 i; i < players.length; i++) {
            path[0] = players[i].token;
            swapper.swapExactTokensForTokens(
                ticketCost,
                1,
                path,
                address(this),
                block.timestamp + 1
            );
        }

        // Aave Pool
        IERC20(_tokenAddr).approve(
            poolAddress,
            IERC20(_tokenAddr).balanceOf(address(this))
        );

        ILendingPool(poolAddress).deposit(
            _tokenAddr,
            IERC20(_tokenAddr).balanceOf(address(this)),
            address(this),
            0
        );
    }

    function closeLottery() public onlyOwner {
        require(
            lotteryStatus == LotteryStatus.STARTED,
            "Lottery is not started"
        );
        require(winnerNumber > 0, "RANDOM_NUMBER_ERROR");

        lotteryStatus = LotteryStatus.CLOSE;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getRandomNumber() public returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= feeVRF,
            "Not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, feeVRF);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        require(msg.sender == vrfCoordinator, "Only permitted by Coordinator");
        winnerNumber = randomness;
    }
}
