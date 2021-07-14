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
        MAX_SUPPLY: 1,000,000,000 ARTIS
        DECIMAL: 18
        DISTRIBUTION METHOD: 
            Minted all at genesis block.
            Distributed out of Developer account according to whitepaper (artislife.network)
    */
    constructor() ERC777("ArtisLife Network Token", "ARTIS", new address[](0)) {
        _mint(msg.sender, 1000000000 * 10 ** 18, "", "");
    }
}
