//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ArtisLifeNFT.sol";

contract BasicStaking is IERC777Recipient, IERC777Sender {
    using SafeMath for uint256;
    address public artisAddress;
    ERC777 public artisToken;
    address public nftMinterContractAddress;
    ArtisLifeNFTEditions public nftMinter;
    uint256 public TotalValueLocked;
    uint256 public feesCollected;
    uint256 public creationTime = block.timestamp;
    uint256 public constant _WITHDRAWTIMELOCK = 5 minutes;
    uint256 public constant _DEPOSITWINDOW = 7 days;
    address public ADMIN_ROLE;
    IERC1820Registry private _erc1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");
    event NFTEditionClaimed(
        bytes id,
        uint256 edition,
        address staker,
        uint256 timeLocked
    );
    event NewPoolCreated(
        bytes id,
        uint256 totalSupply,
        uint256 remaining,
        uint256 stakingPrice,
        uint256 fee,
        address artistAddress,
        uint256 creationTime,
        string uri
    );
    event StakeReleasedNFTMinted(
        bytes nftID,
        uint256 editionNum,
        address receiver
    );

    //pools represented by nft id that points to the pool
    //contributors and their balances
    struct nft_object {
        bool isValue;
        bytes id;
        uint256 TOTAL_SUPPLY;
        uint256 amountLeftToClaim;
        uint256 stakingPrice;
        uint256 creationTime;
        address artistAddress;
        uint256 maxPayout;
        bool settled;
        mapping(uint256 => address) editionsClaimed;
        mapping(address => uint256) stakingPool;
        mapping(address => uint256) stakingTimeLocks;
        string nftMetaData;
        uint256 networkFee;
    }
    //store all nft addresses with their added date
    mapping(bytes => nft_object) allNFTs;
    bytes[] public allNFTPoolIDs;
    uint256 public totalNFTIDs;

    constructor() payable {
        artisAddress = 0xC8625f6efbfd3d2e478D117c08CCD648B2525D62;
        artisToken = ERC777(artisAddress);
        nftMinterContractAddress = 0xC46482c0706Da23b2300083f5a89BCDD4931d4AE;
        nftMinter = ArtisLifeNFTEditions(nftMinterContractAddress);
        ADMIN_ROLE = msg.sender;
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
    }

    modifier depositLocked(bytes calldata nftID) {
        require(
            allNFTs[nftID].creationTime.add(_DEPOSITWINDOW) >= block.timestamp,
            "Deposit function is timelocked"
        );
        _;
    }

    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {}

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata nftID,
        bytes calldata operatorData
    ) external override {
        if(from == ADMIN_ROLE && !allNFTs[nftID].isValue){
            TotalValueLocked = TotalValueLocked.add(amount);
            return;
        }
        require(
            artisToken.balanceOf(to) == amount.add(TotalValueLocked),
            "Only ARTIS accepted."
        );
        require(allNFTs[nftID].isValue, "Pool does not exist!");
        require(
            allNFTs[nftID].creationTime.add(_DEPOSITWINDOW) >= block.timestamp,
            "Deposit function is timelocked"
        );
        require(
            amount == allNFTs[nftID].stakingPrice,
            "Funds sent need to equal staking price exactly."
        );
        require(allNFTs[nftID].amountLeftToClaim != 0, "No NFTs available.");
        require(
            allNFTs[nftID].amountLeftToClaim >= 1,
            "Not enough NFTs left for that amount."
        );
        //Record the edition that is claimed (total .sub( amountLeft)
        uint256 edition =
            allNFTs[nftID].TOTAL_SUPPLY.sub(allNFTs[nftID].amountLeftToClaim);
        allNFTs[nftID].editionsClaimed[edition] = from;
        //Add funds to msg.sender account & start the timelock
        allNFTs[nftID].stakingPool[from] = allNFTs[nftID].stakingPool[from].add(
            amount
        );
        allNFTs[nftID].stakingTimeLocks[from] = block.timestamp;
        emit NFTEditionClaimed(
            nftID,
            edition,
            from,
            allNFTs[nftID].stakingTimeLocks[from]
        );
        TotalValueLocked = TotalValueLocked.add(amount);
        feesCollected = feesCollected.add(allNFTs[nftID].networkFee);
        //Decrease the amount of NFTs available by 1
        allNFTs[nftID].amountLeftToClaim = allNFTs[nftID].amountLeftToClaim.sub(
            1
        );
    }

    modifier onlyOwner() {
        require(ADMIN_ROLE == msg.sender, "Caller not owner.");
        _;
    }

    modifier poolNotExist(bytes calldata nftID) {
        require(!allNFTs[nftID].isValue, "Pool exists already!");
        _;
    }

    modifier poolExist(bytes calldata nftID) {
        require(allNFTs[nftID].isValue, "Pool does not exist!");
        _;
    }

    modifier withdrawLocked(bytes calldata nftID, address account) {
        require(
            allNFTs[nftID].stakingTimeLocks[account].add(_WITHDRAWTIMELOCK) <=
                block.timestamp,
            "Withdrawal function is timelocked"
        );
        _;
    }

    function nftRemaining(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].amountLeftToClaim;
    }

    function nftStakePrice(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].stakingPrice;
    }

    function nftWithdrawTime(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return
            allNFTs[nftID].stakingTimeLocks[msg.sender].add(_WITHDRAWTIMELOCK);
    }

    function nftEndingTime(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].creationTime.add(_DEPOSITWINDOW);
    }

    function nftTotalSupply(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].TOTAL_SUPPLY;
    }

    function nftFindEdition(bytes calldata nftID, uint256 edition)
        public
        view
        poolExist(nftID)
        returns (address)
    {
        return allNFTs[nftID].editionsClaimed[edition];
    }

    function canDeposit(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (bool)
    {
        return
            allNFTs[nftID].creationTime.add(_DEPOSITWINDOW) >= block.timestamp;
    }

    function canWithdraw(bytes calldata nftID, address account)
        public
        view
        poolExist(nftID)
        returns (bool)
    {
        return
            allNFTs[nftID].stakingTimeLocks[account].add(_WITHDRAWTIMELOCK) <=
            block.timestamp;
    }

    function hasDeposit(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return
            allNFTs[nftID].stakingPool[msg.sender] != 0
                ? allNFTs[nftID].stakingPool[msg.sender]
                : 0;
    }

    function getFee(bytes calldata nftID) public view returns (uint256) {
        return allNFTs[nftID].networkFee;
    }

    function withdraw(
        bytes calldata nftID,
        uint256 unftID,
        uint256 editionNum
    ) public poolExist(nftID) withdrawLocked(nftID, msg.sender) {
        require(
            (allNFTs[nftID].stakingPool[msg.sender] > 0),
            "No funds to withdraw."
        );
        require(
            allNFTs[nftID].editionsClaimed[editionNum] == msg.sender,
            "No priviledges to mint NFT."
        );
        nftMinter.mintFor(msg.sender, unftID, 1, editionNum, "");
        allNFTs[nftID].editionsClaimed[editionNum] = address(0);
        artisToken.send(
            msg.sender,
            allNFTs[nftID].stakingPrice.sub(allNFTs[nftID].networkFee),
            abi.encodePacked(nftID)
        );
        allNFTs[nftID].stakingPool[msg.sender] = allNFTs[nftID].stakingPool[
            msg.sender
        ]
            .sub(allNFTs[nftID].stakingPrice);
        TotalValueLocked = TotalValueLocked.sub(
            allNFTs[nftID].stakingPrice.sub(allNFTs[nftID].networkFee)
        );
        emit StakeReleasedNFTMinted(nftID, editionNum, msg.sender);
    }

    function createNFTPool(
        bytes calldata nftID,
        uint256 totalSupply,
        uint256 stakingPrice,
        uint256 fee,
        address artistAddress,
        uint256 maxPayout,
        string memory uri
    ) public onlyOwner() poolNotExist(nftID) {
        artisToken.operatorSend(msg.sender, address(this), maxPayout, nftID, "");
        allNFTs[nftID].artistAddress = artistAddress;
        allNFTs[nftID].maxPayout = maxPayout;
        allNFTs[nftID].isValue = true;
        allNFTs[nftID].TOTAL_SUPPLY = totalSupply;
        allNFTs[nftID].amountLeftToClaim = totalSupply;
        allNFTs[nftID].stakingPrice = stakingPrice;
        uint256 timestamp = block.timestamp;
        allNFTs[nftID].creationTime = timestamp;
        allNFTs[nftID].nftMetaData = uri;
        allNFTs[nftID].networkFee = fee;
        allNFTPoolIDs.push(nftID);
        totalNFTIDs = totalNFTIDs.add(1);
        emit NewPoolCreated(
            nftID,
            totalSupply,
            totalSupply,
            stakingPrice,
            fee,
            artistAddress,
            timestamp,
            uri
        );
    }

    function artistPayout(bytes calldata nftID) public {
        require(
            allNFTs[nftID].artistAddress == msg.sender,
            "Must call function from artist address."
        );
        require(allNFTs[nftID].settled == false, "Already paid out.");
        require(canDeposit(nftID) == false, "Payout not available yet.");
        uint256 payout =
            allNFTs[nftID].maxPayout.mul(
                (
                    allNFTs[nftID].amountLeftToClaim.div(
                        allNFTs[nftID].TOTAL_SUPPLY
                    )
                )
            );
        allNFTs[nftID].maxPayout = allNFTs[nftID].maxPayout.sub(payout);
        artisToken.send(msg.sender, payout, abi.encodePacked(nftID));
        allNFTs[nftID].settled = true;
        TotalValueLocked = TotalValueLocked.sub(payout);
    }

    function collectLeftoverFunds(bytes calldata nftID) public onlyOwner() {
        require(allNFTs[nftID].settled == true, "Not settled yet.");
        artisToken.send(
            msg.sender,
            allNFTs[nftID].maxPayout,
            abi.encodePacked(nftID)
        );
        TotalValueLocked = TotalValueLocked.sub(allNFTs[nftID].maxPayout);
        allNFTs[nftID].maxPayout = 0;
    }

    function unlockFunction(bytes calldata nftID)
        public
        onlyOwner()
        poolExist(nftID)
    {
        allNFTs[nftID].creationTime = 0;
    }

    function collectFees() public onlyOwner() {
        artisToken.send(
            msg.sender,
            feesCollected,
            abi.encodePacked("Collected Fees.")
        );
        TotalValueLocked = TotalValueLocked.sub(feesCollected);
        feesCollected = 0;
    }

    function setERC777Address(address _erc) public onlyOwner() {
        artisAddress = _erc;
        artisToken = ERC777(artisAddress);
    }

    function setNewMinter(address _minter) public onlyOwner() {
        nftMinterContractAddress = _minter;
        nftMinter = ArtisLifeNFTEditions(nftMinterContractAddress);
    }

    function setFee(bytes calldata nftID, uint256 _fee) public onlyOwner() {
        allNFTs[nftID].networkFee = _fee;
    }
}
