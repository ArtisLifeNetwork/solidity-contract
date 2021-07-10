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
    ArtisLifeNFT public nftMinter;
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
        nftMinter = ArtisLifeNFT(nftMinterContractAddress);
        ADMIN_ROLE = msg.sender;
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
    }

    /*
        onlyOwner

        Checks if sender is owner of contract
    */
    modifier onlyOwner() {
        require(ADMIN_ROLE == msg.sender, "Caller not owner.");
        _;
    }

    /*
        poolNotExist

        Checks if pool does not exist for given nftID
    */
    modifier poolNotExist(bytes calldata nftID) {
        require(!allNFTs[nftID].isValue, "Pool exists already!");
        _;
    }

    /*
        poolExists

        Checks if pool exists for given nftID
    */
    modifier poolExist(bytes calldata nftID) {
        require(allNFTs[nftID].isValue, "Pool does not exist!");
        _;
    }

    /*
        depositLocked

        Checks if user can deposit for given nftID
    */
    modifier depositLocked(bytes calldata nftID) {
        require(
            allNFTs[nftID].creationTime.add(_DEPOSITWINDOW) >= block.timestamp,
            "Deposit function is timelocked"
        );
        _;
    }

    /*
        withdrawLocked

        Checks if user can withdraw for given nftID
    */
    modifier withdrawLocked(bytes calldata nftID, address account) {
        require(
            allNFTs[nftID].stakingTimeLocks[account].add(_WITHDRAWTIMELOCK) <=
                block.timestamp,
            "Withdrawal function is timelocked"
        );
        _;
    }

    /*
        nftRemaining

        Checks if there are unclaimied NFTs for given nftID
    */
    function nftRemaining(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].amountLeftToClaim;
    }

    /*
        nftStakePrice

        Checks the staking price for given nftID
    */
    function nftStakePrice(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].stakingPrice;
    }

    /*
        nftWithdrawTime

        Checks what time withdrawals are allowed for given nftID
    */
    function nftWithdrawTime(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return
            allNFTs[nftID].stakingTimeLocks[msg.sender].add(_WITHDRAWTIMELOCK);
    }

    /*
        nftEndingTime

        Checks what time deposits are expired for given nftID
    */
    function nftEndingTime(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].creationTime.add(_DEPOSITWINDOW);
    }

    /*
        nftTotalSupply

        Checks the total supply for given nftID
    */
    function nftTotalSupply(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (uint256)
    {
        return allNFTs[nftID].TOTAL_SUPPLY;
    }

    /*
        nftFindEdition

        Checks if user has claimed edition for given nftID
    */
    function nftFindEdition(bytes calldata nftID, uint256 edition)
        public
        view
        poolExist(nftID)
        returns (address)
    {
        return allNFTs[nftID].editionsClaimed[edition];
    }

    /*
        canDeposit

        Checks if user can deposit for given nftID
    */
    function canDeposit(bytes calldata nftID)
        public
        view
        poolExist(nftID)
        returns (bool)
    {
        return
            allNFTs[nftID].creationTime.add(_DEPOSITWINDOW) >= block.timestamp;
    }

    /*
        canWithdraw

        Checks if user can withdraw for given nftID
    */
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

    /*
        getFee

        Gets network fee of given nftID
    */
    function getFee(bytes calldata nftID) public view returns (uint256) {
        return allNFTs[nftID].networkFee;
    }

    /*
        hasDeposit

        Checks for balance of given nftID
    */
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

    /*
        tokensToSend

        Disabled until needed.
    */
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {}

    /*
        tokenReceived

        Begins staking period for given nftID. Deposits token into
        corresponding pool and logs the starting time. Tokens sent
        must exactly equal staking price.
    */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata nftID,
        bytes calldata operatorData
    ) external override {
        if (from == ADMIN_ROLE && !allNFTs[nftID].isValue) {
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
        uint256 edition = allNFTs[nftID].TOTAL_SUPPLY.sub(
            allNFTs[nftID].amountLeftToClaim
        );
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

    /*
        withdraw

        Mints corresponding NFT directly to the sender's wallet then 
        withdraws the original staking requirement minus the network fee. 
    */
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
        allNFTs[nftID].stakingPool[msg.sender] = allNFTs[nftID]
        .stakingPool[msg.sender]
        .sub(allNFTs[nftID].stakingPrice);
        TotalValueLocked = TotalValueLocked.sub(
            allNFTs[nftID].stakingPrice.sub(allNFTs[nftID].networkFee)
        );
        emit StakeReleasedNFTMinted(nftID, editionNum, msg.sender);
    }

    /*
        createNFTPool

        Admin function used to create a new pool entry.
    */
    function createNFTPool(
        bytes calldata nftID,
        uint256 totalSupply,
        uint256 stakingPrice,
        uint256 fee,
        address artistAddress,
        uint256 maxPayout,
        string memory uri
    ) public onlyOwner() poolNotExist(nftID) {
        artisToken.operatorSend(
            msg.sender,
            address(this),
            maxPayout,
            nftID,
            ""
        );
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

    /*
        artisPayout

        Withdraws tokens and gives the artist their payout.
        The payout is calculated by max payout multiplied by [ NFT minted / NFT total supply ]
    */
    function artistPayout(bytes calldata nftID) public {
        require(
            allNFTs[nftID].artistAddress == msg.sender,
            "Must call function from artist address."
        );
        require(allNFTs[nftID].settled == false, "Already paid out.");
        require(canDeposit(nftID) == false, "Payout not available yet.");
        uint256 payout = allNFTs[nftID].maxPayout.mul(
            (allNFTs[nftID].amountLeftToClaim.div(allNFTs[nftID].TOTAL_SUPPLY))
        );
        allNFTs[nftID].maxPayout = allNFTs[nftID].maxPayout.sub(payout);
        artisToken.send(msg.sender, payout, abi.encodePacked(nftID));
        allNFTs[nftID].settled = true;
        TotalValueLocked = TotalValueLocked.sub(payout);
    }

    /*
        collectLeftoverFunds

        Admin function used to withdraw funds that the artist did
        not earn. This is the max payout minus the actual payout.
        The pool has had to have been settled already to execute this function.
    */
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

    /*
        unlockFunction

        Admin function used to disable the timelock a staking pool for
        an unforseen circumstance.
    */
    function unlockFunction(bytes calldata nftID)
        public
        onlyOwner()
        poolExist(nftID)
    {
        allNFTs[nftID].creationTime = 0;
    }

    /*
        collectFees

        Admin function used to withdraw the fees that have
        been collected on the network thus far. 
    */
    function collectFees() public onlyOwner() {
        artisToken.send(
            msg.sender,
            feesCollected,
            abi.encodePacked("Collected Fees.")
        );
        TotalValueLocked = TotalValueLocked.sub(feesCollected);
        feesCollected = 0;
    }

    /*
        setERC777Address

        Update the token address used for staking.
    */
    function setERC777Address(address _erc) public onlyOwner() {
        artisAddress = _erc;
        artisToken = ERC777(artisAddress);
    }

    /*
        setNewMinter

        Update the minter address.
    */
    function setNewMinter(address _minter) public onlyOwner() {
        nftMinterContractAddress = _minter;
        nftMinter = ArtisLifeNFT(nftMinterContractAddress);
    }

    /*
        setFee

        Update the network fee of the given nftID.
    */
    function setFee(bytes calldata nftID, uint256 _fee) public onlyOwner() {
        allNFTs[nftID].networkFee = _fee;
    }
}
