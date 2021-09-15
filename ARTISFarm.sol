pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

contract ArtisFarm is IERC777Recipient {
    using SafeMath for uint256;
    mapping(address => stakerObject) public stakers;
    uint256 public rate; //time length for interest
    uint256 public interestAPR; //amount of interest given

    struct stakerObject {
        bool isStaking;
        uint256 startTime;
        uint256 artisBalance;
        address addr;
    }

    //ERC777 Recipient Info
    IERC1820Registry private _erc1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");
    string public name = "ArtisLife Network Farm";

    uint256 public totalARTISLocked;
    uint256 public totalARTISRewards;

    address public ADMIN_ROLE;

    ERC777 public artisToken;

    event RewardsAdded(uint256 amount);
    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event Compound(address indexed to, uint256 amount);

    constructor() {
        artisToken = ERC777(0x8EC776d8Eda7275aa566794D6578eF607C32a02C);
        //Register as ERC777 receiver
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
        rate = 31536000;
        interestAPR = 40;
        ADMIN_ROLE = msg.sender;
    }

    /*
        tokensReceived

        Function that is triggered after receiving any tokens. This contract only accepts 
        ARTIS token.
        Total Value Locked is updated.
    */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {
        if (from == ADMIN_ROLE) {
            return;
        }
        require(
            artisToken.balanceOf(to) > totalARTISLocked,
            "Only ARTIS accepted."
        );
        require(amount > 0, "Must stake more than zero.");
        if (stakers[from].isStaking == true) {
            uint256 toTransfer = calculateYieldTotal(from);
            stakers[from].artisBalance = stakers[from].artisBalance.add(
                toTransfer
            );
            totalARTISRewards = totalARTISRewards.sub(toTransfer);
            totalARTISLocked = totalARTISLocked.add(toTransfer);
        }
        stakers[from].artisBalance = stakers[from].artisBalance.add(amount);
        totalARTISLocked = totalARTISLocked.add(amount);
        stakers[from].startTime = block.timestamp;
        stakers[from].isStaking = true;
        stakers[from].addr = from;
        emit Stake(from, amount);
    }

    function addRewards(uint256 amount) public {
        require(
            amount > 0 && artisToken.balanceOf(msg.sender) >= amount,
            "You cannot stake zero tokens"
        );
        artisToken.transferFrom(msg.sender, address(this), amount);
        totalARTISRewards = totalARTISRewards.add(amount);
        emit RewardsAdded(amount);
    }

    function compoundYield() external {
        compoundYield(msg.sender);
    }

    function compoundYield(address staker) private {
        require(
            stakers[staker].isStaking =
                true &&
                stakers[staker].artisBalance > 0,
            "Nothing to unstake"
        );
        uint256 yield = calculateYieldTotal(staker);
        stakers[staker].startTime = block.timestamp;
        stakers[staker].artisBalance = stakers[staker].artisBalance.add(yield);
        totalARTISLocked = totalARTISLocked.add(yield);
        totalARTISRewards = totalARTISRewards.sub(yield);
        emit Compound(staker, yield);
    }

    function compoundBatch(address[] memory _stakers) external onlyAdmin {
        for (uint256 i = 0; i < _stakers.length; i++) {
            compoundYield(_stakers[i]);
        }
    }

    function unstake(uint256 amount) public {
        require(
            stakers[msg.sender].isStaking =
                true &&
                stakers[msg.sender].artisBalance >= amount,
            "Nothing to unstake"
        );
        uint256 yield = calculateYieldTotal(msg.sender);
        totalARTISRewards = totalARTISRewards.sub(yield);
        totalARTISLocked = totalARTISLocked.sub(amount);
        stakers[msg.sender].startTime = block.timestamp;
        stakers[msg.sender].artisBalance = stakers[msg.sender].artisBalance.sub(
            amount
        );
        artisToken.send(msg.sender, amount.add(yield), "");
        if (stakers[msg.sender].artisBalance == 0) {
            stakers[msg.sender].isStaking = false;
        }
        emit Unstake(msg.sender, amount);
    }

    function unstakeAll() external {
        require(stakers[msg.sender].artisBalance > 0, "Nothing to unstake");
        uint256 amount = stakers[msg.sender].artisBalance;
        unstake(amount);
    }

    function calculateYieldTime(address user) public view returns (uint256) {
        uint256 end = block.timestamp;
        uint256 totalTime = end.sub(stakers[user].startTime);
        return totalTime;
    }

    function calculateYieldTotal(address user) public view returns (uint256) {
        uint256 time = calculateYieldTime(user).mul(10**18);
        uint256 timeRate = time.div(rate);
        uint256 rawYield = stakers[user]
            .artisBalance
            .mul(interestAPR.mul(10**18).div(100))
            .div(10**18)
            .mul(timeRate)
            .div(10**18);
        if (rawYield > totalARTISRewards) return totalARTISRewards;
        return rawYield;
    }

    function emergencyWithdraw() external onlyAdmin {
        artisToken.send(
            ADMIN_ROLE,
            artisToken.balanceOf(address(this)),
            "Emergency Withdraw"
        );
    }

    function emergencyWithdrawRewards() external onlyAdmin {
        artisToken.send(
            ADMIN_ROLE,
            totalARTISRewards,
            "Emergency Withdraw Rewards"
        );
    }

    function setRate(uint256 newRate) external onlyAdmin {
        rate = newRate;
    }
    
    function setInterestAPR(uint256 newRate) external onlyAdmin {
        interestAPR = newRate;
    }


    modifier onlyAdmin() {
        require(msg.sender == ADMIN_ROLE, "Must be Admin.");
        _;
    }
}
