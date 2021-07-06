//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract Token is ERC777 {
    constructor() ERC777("ArtisLife Token", "ARTIS", new address[](0)) {
        _mint(msg.sender, 1000000000 * 10 ** 18, "", "");
    }
}
