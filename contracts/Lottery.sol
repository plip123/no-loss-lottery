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

    struct MyLottery {
        uint256 id;
        uint256 ticketCost;
        uint256 fee;
        address poolAddress;
        address tokenPoolAddress;
        uint256 lastPrize;
        address winner;
        bool isClose;
    }

    struct Player {
        uint256 id;
        address player;
        address token;
    }

    IUniswapV2Router internal constant swapper =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    LotteryStatus public lotteryStatus;
    uint256 public lotteryId;
    uint256 internal lotteryTime;
    uint256 internal lotteryBalance;
    address private lotteryAdmin;
    address public recipientAddr;
    Player[] public players;

    bytes32 internal keyHash;
    uint256 internal feeVRF;
    uint256 public winnerNumber;
    address private vrfCoordinator;

    mapping(address => address) currencies;
    mapping(address => uint256) playerId;
    mapping(uint256 => Player[]) lotteryRecord;
    mapping(uint256 => MyLottery) lotteries;

    event NewPlayer(address player, uint256 ticketId, uint256 lotteryID);
    event OpenLottery(
        uint256 id,
        LotteryStatus status,
        address tokenAddr,
        uint256 ticketCost
    );
    event StartLottery(
        uint256 id,
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
     */
    function initialize(address _recipient, address _vrfCoordinator)
        public
        initializer
    {
        vrfCoordinator = _vrfCoordinator;
        VRFConsumerBaseUpgradable.initializeVRF(
            vrfCoordinator, // VRF Coordinator
            0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token
        );

        lotteryAdmin = msg.sender;
        recipientAddr = _recipient;
        lotteryTime = 0;
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
            IERC20(tokenAddr).balanceOf(msg.sender) >=
                lotteries[lotteryId].ticketCost,
            "Balance not enough"
        );
        require(
            playerId[msg.sender] == 0,
            "You are participating in this lottery"
        );

        IERC20(tokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            lotteries[lotteryId].ticketCost
        );

        players.push(Player(lotteryId, msg.sender, tokenAddr));
        playerId[msg.sender] = players.length;

        emit NewPlayer(msg.sender, playerId[msg.sender], lotteryId);
    }

    /**
     * Lottery ticket purchase time begins
     * @param _tokenAddr Address of the token to be used in the pool
     * @param _poolAddress Address of the pool where interest will be earned
     * @param _ticketCost Lottery ticket cost
     */
    function openLottery(
        address _tokenAddr,
        address _poolAddress,
        uint256 _ticketCost
    ) public isAdmin {
        require(
            lotteryStatus == LotteryStatus.CLOSE && lotteryTime == 0,
            "Lottery in progress"
        );
        require(_tokenAddr == currencies[_tokenAddr], "Currency is desactived");
        lotteryBalance = 0;

        for (uint256 i = 0; i < players.length; i++) {
            playerId[players[i].player] = 0;
        }

        delete players;
        console.log(block.timestamp);
        lotteryId += 1;
        lotteries[lotteryId] = MyLottery(
            lotteryId,
            _ticketCost,
            5,
            _poolAddress,
            _tokenAddr,
            0,
            address(0),
            false
        );
        lotteryTime = block.timestamp + 2 days;
        lotteryStatus = LotteryStatus.OPEN;
        emit OpenLottery(
            lotteryId,
            lotteryStatus,
            lotteries[lotteryId].tokenPoolAddress,
            _ticketCost
        );
    }

    /**
     * Initiates time to generate interest
     */
    function startLottery() public isAdmin {
        require(
            lotteryStatus == LotteryStatus.OPEN &&
                lotteryTime < block.timestamp,
            "Lottery is not open"
        );
        require(players.length > 0, "Not enough players");
        address[] memory path = new address[](2);
        path[1] = lotteries[lotteryId].tokenPoolAddress;
        address[] memory curr = new address[](5);
        curr[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        curr[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        curr[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        curr[3] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        curr[4] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // BUSD

        lotteryTime = block.timestamp + 5 days;
        lotteryStatus = LotteryStatus.STARTED;

        uint256 balance = 0;
        for (uint256 i = 0; i < 5; i++) {
            balance = IERC20(curr[i]).balanceOf(address(this));
            if (
                balance > 0 && curr[i] != lotteries[lotteryId].tokenPoolAddress
            ) {
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

        lotteryBalance = IERC20(lotteries[lotteryId].tokenPoolAddress)
            .balanceOf(address(this));

        // Aave Pool
        IERC20(lotteries[lotteryId].tokenPoolAddress).approve(
            lotteries[lotteryId].poolAddress,
            lotteryBalance
        );

        ILendingPool(lotteries[lotteryId].poolAddress).deposit(
            lotteries[lotteryId].tokenPoolAddress,
            lotteryBalance,
            address(this),
            0
        );
        console.log(block.timestamp);
        console.log(
            "Balance",
            IERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3).balanceOf(
                address(this)
            )
        );
        emit StartLottery(
            lotteryId,
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
            lotteryStatus == LotteryStatus.STARTED &&
                lotteryTime < block.timestamp,
            "Lottery is not started"
        );
        require(winnerNumber > 0, "RANDOM_NUMBER_ERROR");

        Player memory player = players[winnerNumber.mod(players.length)];
        MyLottery storage lott = lotteries[lotteryId];
        lott.winner = player.player;
        lotteryRecord[lotteryId] = players;

        lotteryTime = 0;
        lotteryStatus = LotteryStatus.CLOSE;
        lott.isClose = true;

        console.log(
            "Balance Withdraw",
            IERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3).balanceOf(
                address(this)
            )
        );

        uint256 balancePool = ILendingPool(lott.poolAddress).withdraw(
            lott.tokenPoolAddress,
            ~uint256(0), //lotteryBalance,
            address(this)
        );

        uint256 interests = balancePool.sub(lotteryBalance);
        uint256 lastFee = interests.mul(lott.fee).div(100);
        lott.lastPrize = interests.sub(lastFee);

        IERC20(lott.tokenPoolAddress).transferFrom(
            address(this),
            recipientAddr,
            lastFee
        );

        emit CloseLottery(
            lotteryId,
            player.player,
            lotteryStatus,
            players.length
        );
    }

    /**
     * The player can withdraw his/her lottery funds
     * @param _lotteryId Lottery number to which the funds are to be claimed
     * @param _ticketId Ticket number to which funds are to be claimed
     */
    function claim(uint256 _lotteryId, uint256 _ticketId) public {
        require(lotteries[_lotteryId].isClose, "Lottery is not close");
        require(msg.sender != address(0), "Invalid user");

        Player memory player = lotteryRecord[_lotteryId][_ticketId.sub(1)];

        require(msg.sender == player.player, "Invalid user ticket");
        console.log(block.timestamp);

        if (msg.sender != lotteries[_lotteryId].winner) {
            IERC20(lotteries[_lotteryId].tokenPoolAddress).safeTransferFrom(
                address(this),
                msg.sender,
                lotteries[_lotteryId].ticketCost
            );
        } else {
            IERC20(lotteries[_lotteryId].tokenPoolAddress).safeTransferFrom(
                address(this),
                msg.sender,
                lotteries[_lotteryId].ticketCost +
                    lotteries[_lotteryId].lastPrize
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
