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
    This contract will be deployed 3 seperate times to symbolize the 3 different vesting
    "funds" on the network: APF, RDF, Private Sale. More info on
    our whitepaper in section 3 ARTIS Tokenomics.
    All relevant variables are public for community trust.
*/
contract PresaleTokenLockup is IERC777Recipient {
    using SafeMath for uint256;

    //ERC777 Recipient Info
    IERC1820Registry private _erc1820 =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");

    //Variable to hold ARTIS token object
    ERC777 public artisToken;
    ERC777 public artisPresaleToken;
    uint256 public TotalPresaleTokens;

    //Total ARTIS tokens this contract is holding.
    uint256 public TotalValueLocked;
    //Total ARTIS tokens this contract has held.
    uint256 public TotalValueHeld;

    //Address to Admin Priviledges
    address public ADMIN_ROLE;

    //Variables to keep track of timelock from time of contract creation
    uint256 public _TIMELOCKSTART = block.timestamp;
    uint256 public _TIMELOCK;

    //Map pointing addresses to token allocations
    mapping(address => uint256) public tokenAllocations;
    uint256 public sumOfAllocations;

    //Map pointing addresses to withdrawals
    mapping(address => uint256) public recipientWithdrawals;

    //Default constructor
    constructor(
        uint256 timelock,
        address artis,
        address artisp
    ) payable {
        //Set ARTIS token api
        artisToken = ERC777(artis);
        //Set ARTISp token api
        artisPresaleToken = ERC777(artisp);
        //Register sender as admin
        ADMIN_ROLE = msg.sender;
        //Register as ERC777 receiver
        _erc1820.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
        //Set timelock
        _TIMELOCK = timelock;
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

        Function that is triggered after receiving any tokens. This contract only accepts 
        ARTIS token from admin or ARTISp from any user.
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
        if (
            from == ADMIN_ROLE &&
            artisToken.balanceOf(to) == amount.add(TotalValueLocked)
        ) {
            TotalValueLocked = TotalValueLocked.add(amount);
            TotalValueHeld = TotalValueHeld.add(amount);
        } else {
            require(
                artisPresaleToken.balanceOf(to) ==
                    amount.add(TotalPresaleTokens),
                "Only ARTIS accepted."
            );
            require(
                amount <=
                    TotalValueHeld.sub(sumOfAllocations).add(
                        tokenAllocations[from]
                    ),
                "Not enough tokens for that allocation."
            );
            //Start Timelock and update TVL
            TotalPresaleTokens = TotalPresaleTokens.add(amount);
            tokenAllocations[from] = tokenAllocations[from].add(amount);
            sumOfAllocations = sumOfAllocations.add(tokenAllocations[from]);
        }
    }

    /*
        available

        Returns the amount of tokens that are available for withdrawal.
        Formula:
        If Timelock has completed
            Available = TotalPayout - Withdrawn Tokens 
        Else
            Available = TotalPayout * ( Percent of timelock completed ) - Withdrawed Tokens
    */
    function available() public view returns (uint256) {
        //Seconds that have passed since contract creation
        uint256 timeElapsed = block.timestamp.sub(_TIMELOCKSTART);

        if (_TIMELOCK < timeElapsed)
            return
                tokenAllocations[msg.sender].sub(
                    recipientWithdrawals[msg.sender]
                );
        return
            tokenAllocations[msg.sender].div(_TIMELOCK.div(timeElapsed)).sub(
                recipientWithdrawals[msg.sender]
            );
    }

    /*
        withdraw

        Withdraws all available tokens.
    */
    function withdraw() external {
        require(available() > 0, "No Tokens to Withdraw.");
        //Save available withdraw balance
        uint256 amount = available();

        //Add new withdrawal to existing withdrawals
        recipientWithdrawals[msg.sender] = recipientWithdrawals[msg.sender].add(
            amount
        );
        //Send recipient their ARTIS tokens
        artisToken.operatorSend(
            address(this),
            msg.sender,
            amount,
            abi.encodePacked(amount),
            abi.encodePacked("Presale Withdraw")
        );

        //Update Total Value Locked
        TotalValueLocked = TotalValueLocked.sub(amount);
    }
}