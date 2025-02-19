// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract LotteryToken is ERC721, Ownable, ReentrancyGuard, VRFConsumerBase {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    // Chainlink VRF 配置
    bytes32 internal keyHash;
    uint256 internal fee;

    // 代币唯一编码
    mapping(uint256 => string) public tokenUniqueCode;

    // 中奖历史记录
    struct Winner {
        uint256 tokenId;
        address winner;
        uint256 amount;
        uint256 timestamp;
    }
    Winner[] public winners;

    // 代币总供应量
    uint256 public constant TOTAL_SUPPLY = 1000000000; // 10亿个代币
    uint256 public totalMinted;

    // 中奖池
    uint256 public prizePool;

    // 中奖概率（默认 1%）
    uint256 public winningProbability = 1;

    // 事件
    event TokenMinted(uint256 tokenId, string uniqueCode, address owner);
    event WinnerSelected(uint256 tokenId, address winner, uint256 amount);
    event PrizePoolUpdated(uint256 newPrizePool);

    constructor(
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee
    ) ERC721("LotteryToken", "LTT") VRFConsumerBase(_vrfCoordinator, _linkToken) {
        keyHash = _keyHash;
        fee = _fee;
    }

    // 铸造代币并分配唯一编码
    function mintToken(string memory uniqueCode) external onlyOwner {
        require(totalMinted < TOTAL_SUPPLY, "All tokens minted");
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        totalMinted++;

        // 分配唯一编码
        tokenUniqueCode[tokenId] = uniqueCode;

        // 铸造代币
        _mint(msg.sender, tokenId);

        // 触发事件
        emit TokenMinted(tokenId, uniqueCode, msg.sender);
    }

    // 请求随机数
    function requestRandomWinner() external onlyOwner returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        require(prizePool > 0, "Prize pool is empty");
        return requestRandomness(keyHash, fee);
    }

    // 处理随机数结果
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(totalMinted > 0, "No tokens minted yet");

        // 随机选择一个代币
        uint256 winnerTokenId = (randomness % totalMinted);
        address winner = ownerOf(winnerTokenId);

        // 计算奖励金额
        uint256 prizeAmount = (prizePool * winningProbability) / 100; // 根据中奖概率计算
        require(prizeAmount > 0, "Prize amount is zero");
        prizePool -= prizeAmount;

        // 记录中奖历史
        winners.push(Winner({
            tokenId: winnerTokenId,
            winner: winner,
            amount: prizeAmount,
            timestamp: block.timestamp
        }));

        // 发送奖励
        payable(winner).transfer(prizeAmount);

        // 触发事件
        emit WinnerSelected(winnerTokenId, winner, prizeAmount);
    }

    // 获取中奖历史
    function getWinners() external view returns (Winner[] memory) {
        return winners;
    }

    // 管理员提取合约余额
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner()).transfer(balance);
    }

    // 接收 ETH 作为奖池
    receive() external payable {
        prizePool += msg.value;
        emit PrizePoolUpdated(prizePool);
    }

    // 设置中奖概率（仅管理员）
    function setWinningProbability(uint256 _newProbability) external onlyOwner {
        require(_newProbability > 0 && _newProbability <= 100, "Invalid probability");
        winningProbability = _newProbability;
    }
}
