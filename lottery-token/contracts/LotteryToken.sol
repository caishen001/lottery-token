// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract LotteryToken is ERC20, Ownable, ReentrancyGuard, VRFConsumerBase {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    // 抽奖记录
    Counters.Counter private _lotteryId;
    mapping(uint256 => address) public lotteryWinners;

    // 持有者列表
    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public holderIndex; // 存储持有者在数组中的索引

    // 黑名单
    mapping(address => bool) public blacklist;
    address[] public blacklistArray;

    // 倒计时相关变量
    uint256 public lotteryEndTime; // 抽奖结束时间
    uint256 public constant lotteryDuration = 5 minutes; // 抽奖持续时间（5分钟）

    // Chainlink VRF 相关变量
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;

    // 月度收入统计
    uint256 public monthlyIncome; // 当月收入
    uint256 public lastResetTime; // 上次重置时间
    uint256 public constant resetInterval = 30 days; // 重置间隔（30天）

    // 事件：抽奖开始
    event LotteryStarted(uint256 endTime);
    // 事件：抽奖结束
    event LotteryEnded(address winner, uint256 prizeAmount, uint256 winnerBalance);
    // 事件：用户被加入黑名单
    event UserBlacklisted(address user);
    // 事件：用户被移除黑名单
    event UserUnblacklisted(address user);
    // 事件：月度收入重置
    event MonthlyIncomeReset(uint256 newIncome, uint256 resetTime);
    // 事件：用户被添加到持有者列表
    event HolderAdded(address holder);
    // 事件：用户从持有者列表中移除
    event HolderRemoved(address holder);

    // 构造函数，初始化代币
    constructor(address initialOwner) ERC20("LotteryToken", "LOT") VRFConsumerBase(
        0xc587d9053cd1118f25F645F9E08BB98c9712A4EE, // VRF Coordinator (BSC Mainnet)
        0x404460C6A5EdE2D891e8297795264fDe62ADBB75  // LINK 代币地址 (BSC Mainnet)
    ) Ownable(initialOwner) {
        _mint(msg.sender, 100000000 * 10**18); // 将所有代币铸造给合约部署者

        // Chainlink VRF 配置
        keyHash = 0x114f3da0a805b6a67d6e9cd2ec746f7028f1b7376365af575cfea3550dd1aa04; // Key Hash (BSC Mainnet)
        fee = 0.2 * 10 ** 18; // 0.2 LINK

        // 初始化月度收入统计
        lastResetTime = block.timestamp;
    }

    // 用户参与抽奖
    function participateInLottery() public nonReentrant {
        require(balanceOf(msg.sender) > 0, "You must hold LotteryToken to participate.");
        require(!blacklist[msg.sender], "You are blacklisted and cannot participate.");

        // 如果用户是新持有者，添加到持有者列表
        if (!isHolder[msg.sender]) {
            holders.push(msg.sender);
            holderIndex[msg.sender] = holders.length - 1;
            isHolder[msg.sender] = true;
            emit HolderAdded(msg.sender);
        }

        // 更新月度收入
        updateMonthlyIncome(0); // 不需要支付 ETH
    }

    // 管理员开始抽奖
    function startLottery() public onlyOwner {
        require(holders.length > 0, "No holders to participate in lottery.");
        require(lotteryEndTime == 0, "Lottery is already running.");

        // 设置抽奖结束时间
        lotteryEndTime = block.timestamp + lotteryDuration;

        // 触发抽奖开始事件
        emit LotteryStarted(lotteryEndTime);
    }

    // 管理员结束抽奖
    function endLottery() public onlyOwner nonReentrant {
        require(lotteryEndTime > 0, "Lottery has not started.");
        require(block.timestamp >= lotteryEndTime, "Lottery has not ended yet.");

        // 获取随机数
        getRandomNumber();

        // 随机选择一个中奖者（基于权重）
        address winner = selectWinner();

        // 记录中奖者
        _lotteryId.increment();
        uint256 currentLotteryId = _lotteryId.current();
        lotteryWinners[currentLotteryId] = winner;

        // 将中奖者加入黑名单
        blacklist[winner] = true;
        blacklistArray.push(winner);
        emit UserBlacklisted(winner);

        // 计算奖励（当月收入的 1%）
        uint256 prizeAmount = monthlyIncome.div(100);

        // 发送奖励
        uint256 winnerBalance = balanceOf(winner);
        payable(winner).transfer(prizeAmount);

        // 重置抽奖结束时间
        lotteryEndTime = 0;

        // 触发抽奖结束事件
        emit LotteryEnded(winner, prizeAmount, winnerBalance);
    }

    // 基于权重的随机抽奖
    function selectWinner() internal view returns (address) {
        require(randomResult > 0, "Random number not generated yet");

        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](holders.length);

        // 计算总权重
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 balance = balanceOf(holders[i]);
            weights[i] = balance;
            totalWeight = totalWeight.add(balance);
        }

        // 根据随机数选择中奖者
        uint256 randomNumber = randomResult % totalWeight;
        uint256 cumulativeWeight = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            cumulativeWeight = cumulativeWeight.add(weights[i]);
            if (randomNumber < cumulativeWeight) {
                return holders[i];
            }
        }

        // 如果未找到中奖者，返回最后一个持有者
        return holders[holders.length - 1];
    }

    // 重写 ERC20 的 transfer 函数，动态更新持有者列表
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);

        // 更新持有者列表
        updateHolders(_msgSender(), recipient);

        return true;
    }

    // 重写 ERC20 的 transferFrom 函数，动态更新持有者列表
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        // 更新持有者列表
        updateHolders(sender, recipient);

        return true;
    }

    // 更新持有者列表
    function updateHolders(address sender, address recipient) internal {
        // 如果发送方的余额为 0，移除发送方
        if (balanceOf(sender) == 0 && isHolder[sender]) {
            removeHolder(sender);
        }

        // 如果接收方是新持有者，添加接收方
        if (balanceOf(recipient) > 0 && !isHolder[recipient]) {
            addHolder(recipient);
        }
    }

    // 添加持有者
    function addHolder(address holder) internal {
        holders.push(holder);
        holderIndex[holder] = holders.length - 1;
        isHolder[holder] = true;
        emit HolderAdded(holder);
    }

    // 移除持有者
    function removeHolder(address holder) internal {
        uint256 index = holderIndex[holder];
        holders[index] = holders[holders.length - 1];
        holders.pop();
        isHolder[holder] = false;
        emit HolderRemoved(holder);
    }

    // Chainlink VRF 请求随机数
    function getRandomNumber() internal returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        return requestRandomness(keyHash, fee);
    }

    // Chainlink VRF 回调函数
    function fulfillRandomness(bytes32 /* requestId */, uint256 randomness) internal override {
        randomResult = randomness;
    }

    // 更新月度收入
    function updateMonthlyIncome(uint256 amount) internal {
        // 检查是否需要重置月度收入
        if (block.timestamp >= lastResetTime + resetInterval) {
            monthlyIncome = 0; // 重置月度收入
            lastResetTime = block.timestamp; // 更新重置时间
            emit MonthlyIncomeReset(monthlyIncome, lastResetTime);
        }

        // 增加月度收入
        monthlyIncome = monthlyIncome.add(amount);
    }
}
