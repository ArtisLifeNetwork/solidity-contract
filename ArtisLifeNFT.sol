//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ArtisLifeNFT is ERC1155PresetMinterPauser {
    using SafeMath for uint256;
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    uint256 _tokenIds;
    uint256 public nftCount;
    string public name;
    string public symbol;
    //mapping id to nft count
    mapping(uint256 => bool) public nftIDs;
    event NFTCreated(uint256 nftID, address creator);
    event TransferSingleEdition(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 edition,
        uint256 value
    );

    constructor()
        ERC1155PresetMinterPauser("https://game.example/api/item/{id}.json")
    {
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(OWNER_ROLE, msg.sender);
        name = "ArtisLife Network Minter";
        symbol = "ARTISNFT";
    }

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "Sender not Govern");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Sender not minter");
        _;
    }

    function pause() public override {
        require(false);
    }

    function unpause() public override {
        require(false);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(false, "Use 5 arg mintFor");
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) public override {
        require(false);
    }

    function mintEditionBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        uint256[] calldata editions,
        bytes memory data
    ) public onlyMinter() {
        for (uint256 i = 0; i < ids.length; i++) {
            mintFor(to, ids[i], amounts[i], editions[i], abi.encode(i));
        }
    }

    function createNewNFT(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        address creator
    ) public virtual onlyOwner() {
        nftIDs[nftCount] = true;
        emit NFTCreated(_tokenIds, creator);
        nftCount = nftCount.add(1);
        _tokenIds = _tokenIds.add(1);
    }

    function giveRole(address account) public onlyOwner() {
        grantRole(MINTER_ROLE, account);
    }

    function mintFor(
        address to,
        uint256 id,
        uint256 amount,
        uint256 edition,
        bytes memory data
    ) public virtual onlyMinter() {
        require(nftIDs[id] != false, "NFT doesn't exist");
        emit TransferSingleEdition(msg.sender, address(0), to, id, edition, 1);
        _mint(to, id, amount, abi.encode(edition));
    }
}

contract ArtisLifeNFTEditions is ArtisLifeNFT {
    using SafeMath for uint256;
    mapping(uint256 => nft_data) nftData;
    uint256 public totalSupply;
    struct nft_data {
        uint256 TOTAL_SUPPLY;
        string name;
        string symbol;
        mapping(address => uint256) balanceOf;
        mapping(uint256 => bool) editionsMinted;
        mapping(uint256 => address) editionOwnerships;
    }

    modifier hasBalance(uint256 id, address sender) {
        require(nftData[id].balanceOf[sender] > 0, "No NFTs");
        _;
    }

    function createNewNFT(
        string calldata name,
        string calldata symbol,
        uint256 totalNFTSupply,
        address creator
    ) public override {
        totalSupply = totalSupply.add(1);
        nftData[_tokenIds].name = name;
        nftData[_tokenIds].symbol = symbol;
        nftData[_tokenIds].TOTAL_SUPPLY = totalNFTSupply;
        super.createNewNFT(name, symbol, totalNFTSupply, creator);
    }

    function mintFor(
        address to,
        uint256 id,
        uint256 amount,
        uint256 edition,
        bytes memory data
    ) public override {
        require(nftData[id].TOTAL_SUPPLY > edition, "Edition not availble");
        require(nftData[id].editionsMinted[edition] == false, "Edition minted");
        nftData[id].editionsMinted[edition] = true;
        nftData[id].editionOwnerships[edition] = to;
        nftData[id].balanceOf[to] = nftData[id].balanceOf[to].add(1);
        super.mintFor(to, id, amount, edition, data);
    }

    function balanceOfEdition(
        address account,
        uint256 id,
        uint256 edition
    ) public view returns (bool) {
        return nftData[id].editionOwnerships[edition] == account;
    }

    function balanceOf(address account, uint256 id)
        public
        view
        override
        returns (uint256)
    {
        return nftData[id].balanceOf[account];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        public
        view
        override
        returns (uint256[] memory)
    {
        require(
            ids.length == accounts.length,
            "ERC1155: ids and amounts length mismatch"
        );
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < ids.length; i++) {
            batchBalances[i] = this.balanceOf(accounts[i], ids[i]);
        }
        return batchBalances;
    }

    function highestEdition(address sender, uint256 id)
        private
        view
        returns (uint256)
    {
        for (uint256 i = nftData[id].TOTAL_SUPPLY - 1; i >= 0; i--) {
            if (nftData[id].editionOwnerships[i] == sender) return i;
        }
        revert("No editions");
    }

    function safeBatchTransferFrom(
        address sender,
        address receiver,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public override {
        require(
            ids.length == amounts.length,
            "ERC1155: ids and amounts length mismatch"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            this.safeTransferFrom(sender, receiver, ids[i], amounts[i], data);
        }
    }

    function safeBatchEditionTransferFrom(
        address sender,
        address receiver,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        uint256[] calldata editions,
        bytes calldata data
    ) public {
        require(
            ids.length == amounts.length,
            "ERC1155: ids and amounts length mismatch"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            this.safeEditionTransferFrom(
                sender,
                receiver,
                ids[i],
                amounts[i],
                editions[i],
                data
            );
        }
    }

    function safeTransferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public override hasBalance(id, sender) {
        uint256 edition = highestEdition(sender, id);
        require(nftData[id].editionOwnerships[edition] == sender, "Not Owner");
        emit TransferSingleEdition(
            msg.sender,
            sender,
            receiver,
            id,
            edition,
            1
        );
        nftData[id].editionOwnerships[edition] = receiver;
        nftData[id].balanceOf[sender] -= 1;
        nftData[id].balanceOf[receiver] += 1;
        super.safeTransferFrom(sender, receiver, id, amount, data);
    }

    function safeEditionTransferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount,
        uint256 edition,
        bytes calldata data
    ) public hasBalance(id, sender) {
        require(nftData[id].editionOwnerships[edition] == sender, "Not Owner");
        emit TransferSingleEdition(
            msg.sender,
            sender,
            receiver,
            id,
            edition,
            1
        );
        nftData[id].editionOwnerships[edition] = receiver;
        nftData[id].balanceOf[sender] -= 1;
        nftData[id].balanceOf[receiver] += 1;
        super.safeTransferFrom(sender, receiver, id, amount, data);
    }
}
