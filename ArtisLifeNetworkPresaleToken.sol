//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

/*
    ArtisLife Network Token
    ERC777

    No minting allowed after contract creation.
*/
contract ArtisLifeNetworkToken is ERC777 {
    /*
        NAME: ArtisLife Network Token
        SYMBOL: ARTIS
        MAX_SUPPLY: 50,000,000 ARTIS
        DECIMAL: 18
        DISTRIBUTION METHOD: 
            Minted all at genesis block.
            Redeemable 1:1 for ArtisLife Network Token through a 3-year
            vesting smart contract.
    */
    constructor() ERC777("ArtisLife Network Presale Token [3-year vesting]", "ARTISp", new address[](0)) {
        _mint(msg.sender, 50000000 * 10 ** 18, "", "");
    }
}