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
        address player;
        address token;
        bool winner;
    }

    IUniswapV2Router internal constant swapper =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    LotteryStatus public lotteryStatus;
    uint256 public lotteryId;
    uint256 internal fee;
    uint256 internal lotteryBalance;
    uint256 public ticketCost;
    address private lotteryAdmin;
    address public recipientAddr;
    address internal poolAddress;
    address internal tokenPoolAddress;
    Player[] public players;

    bytes32 internal keyHash;
    uint256 internal feeVRF;
    uint256 public winnerNumber;
    address private vrfCoordinator;

    mapping(bytes32 => uint256) lotteryRecord;
    mapping(address => address) currencies;
    mapping(address => uint256) playerId;

    event NewPlayer(address player, uint256 playerId, uint256 lotteryID);
    event OpenLottery(uint256 id, LotteryStatus status, address tokenAddr);
    event StartLottery(
        uint256 id,
        address poolAddr,
        LotteryStatus status,
        uint256 balance,
        uint256 numPlayers
    );
    event CloseLottery(
        uint256 id,
        address winner,
        LotteryStatus status,
        uint256 numPlayers
    );

    /**
     * Constructor
     * @param _recipient is a fee recipient
     * @param _vrfCoordinator address of the vrf coordinator
     * @param _ticketCost Lottery ticket cost
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

        recipientAddr = lotteryAdmin = _recipient;
        fee = uint256(5);
        ticketCost = _ticketCost;
        lotteryId = 0;
        lotteryStatus = LotteryStatus.CLOSE;

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

    /**
     * The user will be able to buy tickets
     * @param tokenAddr Token with which the ticket is to be purchased
     */
    function buyTicket(address tokenAddr) public {
        require(lotteryStatus == LotteryStatus.OPEN, "The lottery is closed");
        require(msg.sender != address(0), "Invalid user");
        require(tokenAddr == currencies[tokenAddr], "Currency is desactived");
        require(
            IERC20(tokenAddr).balanceOf(msg.sender) >= ticketCost,
            "Balance not enough"
        );
        require(
            playerId[msg.sender] == 0,
            "You are participating in this lottery"
        );

        IERC20(tokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            ticketCost
        );

        players.push(Player(lotteryId, msg.sender, tokenAddr, false));
        playerId[msg.sender] = players.length;

        emit NewPlayer(msg.sender, playerId[msg.sender], lotteryId);
    }

    /**
     * Lottery ticket purchase time begins
     * @param _tokenAddr Address of the token to be used in the pool
     */
    function openLottery(address _tokenAddr) public isAdmin {
        require(lotteryStatus == LotteryStatus.CLOSE, "Lottery in progress");
        require(_tokenAddr == currencies[_tokenAddr], "Currency is desactived");
        tokenPoolAddress = _tokenAddr;
        lotteryBalance = 0;

        for (uint256 i = 0; i < players.length; i++) {
            playerId[players[i].player] = 0;
        }

        delete players;

        lotteryId += 1;
        lotteryStatus = LotteryStatus.OPEN;
        emit OpenLottery(lotteryId, lotteryStatus, tokenPoolAddress);
    }

    /**
     * Initiates time to generate interest
     * @param _poolAddress Address of the pool where interest will be earned
     */
    function startLottery(address _poolAddress) public isAdmin {
        require(lotteryStatus == LotteryStatus.OPEN, "Lottery is not open");
        require(players.length > 0, "Not enough players");
        poolAddress = _poolAddress;
        address[] memory path = new address[](2);
        path[1] = tokenPoolAddress;
        address[] memory curr = new address[](5);
        curr[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        curr[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        curr[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        curr[3] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        curr[4] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // BUSD

        lotteryStatus = LotteryStatus.STARTED;
        uint256 balance = 0;
        for (uint256 i = 0; i < 5; i++) {
            balance = IERC20(curr[i]).balanceOf(address(this));
            if (balance > 0 && curr[i] != tokenPoolAddress) {
                path[0] = curr[i];
                swapper.swapExactTokensForTokens(
                    balance,
                    1,
                    path,
                    address(this),
                    block.timestamp + 1
                );
            }
        }

        lotteryBalance = IERC20(tokenPoolAddress).balanceOf(address(this));

        // Aave Pool
        IERC20(tokenPoolAddress).approve(poolAddress, lotteryBalance);

        ILendingPool(poolAddress).deposit(
            tokenPoolAddress,
            lotteryBalance,
            address(this),
            0
        );

        emit StartLottery(
            lotteryId,
            _poolAddress,
            lotteryStatus,
            lotteryBalance,
            players.length
        );
    }

    /**
     * Closes the lottery, allocates the funds to the winner and returns the
     * cost of the tickets to the losing users.
     */
    function closeLottery() public isAdmin {
        require(
            lotteryStatus == LotteryStatus.STARTED,
            "Lottery is not started"
        );
        require(winnerNumber > 0, "RANDOM_NUMBER_ERROR");

        uint256 idWin = winnerNumber.mod(players.length);
        Player storage player = players[idWin];
        player.winner = true;

        lotteryStatus = LotteryStatus.CLOSE;

        emit CloseLottery(
            lotteryId,
            player.player,
            lotteryStatus,
            players.length
        );
    }

    /**
     * The player can withdraw his/her lottery funds
     */
    function claim() public {
        require(lotteryStatus == LotteryStatus.CLOSE, "Lottery is not close");
        require(msg.sender != address(0), "Invalid user");
        uint256 id = playerId[msg.sender] - 1;

        ILendingPool(poolAddress).withdraw(
            tokenPoolAddress,
            lotteryBalance,
            address(this)
        );

        if (!players[id].winner) {
            IERC20(tokenPoolAddress).safeTransferFrom(
                address(this),
                msg.sender,
                ticketCost
            );
        } else {
            IERC20(tokenPoolAddress).safeTransferFrom(
                address(this),
                msg.sender,
                ticketCost
            );
        }
    }

    /**
     * Random Number Generator with ChainLink
     */
    function getRandomNumber() public isAdmin returns (bytes32 requestId) {
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

    modifier isAdmin() {
        require(msg.sender == lotteryAdmin, "You are not the admin");
        _;
    }
}
