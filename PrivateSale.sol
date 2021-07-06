//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

contract PrivateSale is IERC777Recipient, IERC777Sender {
    IERC1820Registry private _erc1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");

    address public artisAddress;
    ERC777 public artisToken;
    uint256 public TotalValueLocked;
    address public ADMIN_ROLE;
    uint256 public _CREATIONTIME = block.timestamp;
    uint256 private constant _TIMELOCK = 1460 days;
    mapping(address => uint256) investorBalances;
    mapping(address => uint256) investorWithdrawals;

    constructor() payable {
        artisAddress = 0x215cb512CFBFd03f9029e762b00cCc4EF11b16F6;
        artisToken = ERC777(artisAddress);
        ADMIN_ROLE = msg.sender;
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
    }

    modifier onlyAdmin(address caller) {
        require(caller == ADMIN_ROLE, "NO ADMIN PRIVILEDGES.");
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
        bytes calldata data,
        bytes calldata operatorData
    ) external override {
        require(
            artisToken.balanceOf(to) == amount + TotalValueLocked,
            "Only ARTIS accepted."
        );
        TotalValueLocked += amount;
    }

    function addInvestor(address ethAddress, uint256 amount)
        external
        onlyAdmin(msg.sender)
    {
        require(ethAddress != address(0), "Zero address not allowed.");
        investorBalances[ethAddress] = amount;
    }

    function available() internal view returns (uint256){
        return ((investorBalances[msg.sender] *
                (block.timestamp - _CREATIONTIME)) / _TIMELOCK) -
            investorWithdrawals[msg.sender];
    }

    function withdraw() external {
        require(
            available() >
                investorWithdrawals[msg.sender],
            "No Tokens to Withdraw."
        );
        require(TotalValueLocked > available(), "Not enough ARTIS in contract to payout.");
        uint256 availableBefore = available();
        investorWithdrawals[msg.sender] +=
            availableBefore;
        artisToken.transferFrom(address(this), msg.sender, availableBefore);
        TotalValueLocked -= availableBefore;
    }

    function availableTokens() public view returns (uint256) {
        return available();
    }
}
