//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/*
    TokenLockup

    Vesting smart contract that locks tokens for a specified period.
    The tokens are released continuously for the specified period.
    This contract will be deployed 4 seperate times to symbolize the 4 different vesting
    "funds" on the network: APF, RDF, Private and Public Sale. More info on
    our whitepaper in section 3 ARTIS Tokenomics
*/
contract TokenLockup is IERC777Recipient {
    using SafeMath for uint256;

    //ERC777 Recipient Info
    IERC1820Registry private _erc1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");

    //Variable to hold ARTIS token object
    ERC777 public artisToken;

    //Total ARTIS tokens this contract is holding
    uint256 public TotalValueLocked;

    //Address to Admin Priviledges
    address public ADMIN_ROLE;

    //Variables to keep track of timelock from time of contract creation
    uint256 public _CREATIONTIME = block.timestamp;
    uint256 private _TIMELOCK;

    //Map pointing addresses to balances
    mapping(address => uint256) recipientBalances;

    //Map pointing addresses to withdrawals
    mapping(address => uint256) recipientWithdrawals;

    //Default constructor
    constructor(uint256 lockLength, address artis) payable {
        //Set ARTIS token api
        artisToken = ERC777(artis);
        //Register sender as admin
        ADMIN_ROLE = msg.sender;
        //Register as ERC777 receiver
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
        //Set timelock
        _TIMELOCK = lockLength;
    }

    /*
        onlyAdmin

        Checks to see if caller has admin priviledges
    */
    modifier onlyAdmin(address caller) {
        require(caller == ADMIN_ROLE, "NO ADMIN PRIVILEDGES.");
        _;
    }

    /*
        tokensReceived

        Function that is triggered after receiving any tokens. This
        contract only accepts ARTIS token as specified in the
        artisToken and artisAddress variables. Total Value Locked
        is updated.
    */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {
        require(
            artisToken.balanceOf(to) == amount.add(TotalValueLocked),
            "Only ARTIS accepted."
        );
        TotalValueLocked = TotalValueLocked.add(amount);
    }

    /*
        addRecipient

        Adds an entry for a recipient and logs how many total tokens
        are allocated to that address.
    */
    function addRecipient(address ethAddress, uint256 amount)
        external
        onlyAdmin(msg.sender)
    {
        require(ethAddress != address(0), "Zero address not allowed.");
        recipientBalances[ethAddress] = amount;
    }

    /*
        available

        Returns the amount of tokens that are available for withdrawal.

        Available = TotalPayout * ( Percent of timelock completed ) - Withdrawed Tokens
    */
    function available() public view returns (uint256) {
        uint256 percTimeCompleted = (block.timestamp.sub(_CREATIONTIME)).div(_TIMELOCK);
        return
            //Total Token Payout for sender
            recipientBalances[msg.sender]
                //Multiplied by Percent of timelock completed
                .mul(percTimeCompleted > 1 ? 1 : percTimeCompleted)
                //Minus already withdrawed tokens
                .sub(recipientWithdrawals[msg.sender]);
    }

    /*
        withdraw

        Withdraws all available tokens.
    */
    function withdraw() external {
        require(
            available() > 0,
            "No Tokens to Withdraw."
        );
        require(
            TotalValueLocked > available(),
            "Not enough ARTIS in contract to payout."
        );
        //Save available withdraw balance
        uint256 availableBefore = available();

        //Add withdrawal to existing withdrawals
        recipientWithdrawals[msg.sender] = recipientWithdrawals[msg.sender].add(
            availableBefore
        );

        //Send recipient their ARTIS tokens
        artisToken.transferFrom(address(this), msg.sender, availableBefore);

        //Update Total Value Locked
        TotalValueLocked = TotalValueLocked.sub(availableBefore);
    }
}
