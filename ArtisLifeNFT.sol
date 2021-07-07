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

    constructor()
        ERC1155PresetMinterPauser("https://game.example/api/item/{id}.json")
    {
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(OWNER_ROLE, msg.sender);
        name = "ArtisLife Network Minter";
        symbol = "ARTISNFT";
    }

    /*
        onlyOwner

        Function to check if the sender of the transaction is
        the owner of this contract.
    */
    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "Sender not Govern");
        _;
    }

    /*
        onlyMinter

        Function to check if the sender of the transaction has
        minting priviledges.
    */
    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Sender not minter");
        _;
    }

    /*
        giveRole

        Admin function to give the farming contract minting
        rights to all NFTs. If contract is updated, admin will
        use this function to update accordingly.
    */
    function giveRole(address account) public onlyOwner() {
        grantRole(MINTER_ROLE, account);
    }

    /*
        hasBalance

        Function to check if the requested account address has an
        NFT balance of the provided NFT id.
    */
    modifier hasBalance(uint256 id, address sender) {
        require(nftData[id].balanceOf[sender] > 0, "No NFTs");
        _;
    }

    /*
        balanceOfEdition

        Preferred balanceOf function. Returns the balance of total NFTs 
        owned by the provided account address. 
        Edition numbers are preserved.
    */
    function balanceOfEdition(
        address account,
        uint256 id,
        uint256 edition
    ) public view returns (bool) {
        return nftData[id].editionOwnerships[edition] == account;
    }

    /*
        balanceOfEditionBatch

        Preferred balanceOfBatch function. Returns a batch of the balances
        of total NFTs owned by the provide account addresses. 
        Edition numbers are preserved.
    */
    function balanceOfEditionBatch(
        address[] calldata accounts,
        uint256[] calldata ids,
        uint256[] calldata editions
    ) public view returns (bool[] memory) {
        require(
            ids.length == accounts.length,
            "ERC1155: ids and amounts length mismatch"
        );
        bool[] memory batchBalances = new bool[](accounts.length);
        for (uint256 i = 0; i < ids.length; i++) {
            batchBalances[i] = this.balanceOfEdition(
                accounts[i],
                ids[i],
                editions[i]
            );
        }
        return batchBalances;
    }

    /*
        balanceOf

        Returns the balance of total NFTs owned by the provided
        account address. Edition numbers are not returned.
    */
    function balanceOf(address account, uint256 id)
        public
        view
        override
        returns (uint256)
    {
        return nftData[id].balanceOf[account];
    }

    /*
        balanceOfBatch

        Returns a batch of the balances of total NFTs owned by the provided
        account addresses. Edition numbers are not returned.
    */
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

    /*
        highestEdition

        Looks for the highest edition number of NFT id owned
        by the sender's address.
    */
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

    /*
        createNewNFT

        Creates an NFT entry without minting any NFTs.
        Establishes name, symbol, totalSupply and creator.
    */
    function createNewNFT(
        string calldata name,
        string calldata symbol,
        uint256 totalNFTSupply,
        address creator
    ) public virtual onlyOwner() {
        totalSupply = totalSupply.add(1);
        nftData[_tokenIds].name = name;
        nftData[_tokenIds].symbol = symbol;
        nftData[_tokenIds].TOTAL_SUPPLY = totalNFTSupply;
        nftIDs[nftCount] = true;
        emit NFTCreated(_tokenIds, creator);
        nftCount = nftCount.add(1);
        _tokenIds = _tokenIds.add(1);
    }

    /*
        mintFor
        
        Default mint function that requires the edition as a
        parameter. Only one address is allowed to call
        this function. Checks to see if the edition can or has
        been minted.
    */
    function mintFor(
        address to,
        uint256 id,
        uint256 amount,
        uint256 edition,
        bytes memory data
    ) public virtual onlyMinter() {
        require(nftIDs[id] != false, "NFT doesn't exist");
        require(nftData[id].TOTAL_SUPPLY > edition, "Edition not availble");
        require(nftData[id].editionsMinted[edition] == false, "Edition minted");
        nftData[id].editionsMinted[edition] = true;
        nftData[id].editionOwnerships[edition] = to;
        nftData[id].balanceOf[to] = nftData[id].balanceOf[to].add(1);
        emit TransferSingleEdition(msg.sender, address(0), to, id, edition, 1);
        _mint(to, id, amount, abi.encode(edition));
    }

    /*
        mintEditionBatch

        Default mintBatch function that requires the edition as
        a parameter. Only one address is allowed to call this
        function. Calls mintFor function for the entire batch.
    */
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

    /*
        mint

        DISABLED. We only allowing minting through mintFor and
        mintEditionBatch.
    */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(false, "Use 5 arg mintFor");
    }

    /*
        mintBatch

        DISABLED. We only allowing minting through mintFor and
        mintEditionBatch.
    */
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) public override {
        require(false, "Use 5 arg mintEditionBatch");
    }

    /*
        safeEditionTransferFrom

        The prefered transfer method. If a user owns
        more than one edition, they can specify which
        edition they would like to send. Even if the user
        owns one edition, this transfer method will use
        less gas than safeTransferFrom()
    */
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

    /*
        safeTransferFrom

        Override existing transfer function to add functionality of
        preserving edition numbers. If multiple editions are owned, the
        highest edition will be sent
    */
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

    /*
        safeBatchEditionTransferFrom

        The prefered batchTransfer method. If a user owns
        more than one edition, they can specify which
        edition they would like to send. Even if the user
        owns one edition, this transfer method will use
        less gas than safeBatchTransferFrom()
    */
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

    /*
        safeBatchTransferFrom

        Override existing batchTransfer function to add functionality of
        preserving edition numbers. If multiple editions are owned, the
        highest edition will be sent
    */
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

    /*
        pause

        DISABLED. Reason: reduce contract size
    */
    function pause() public override {
        require(false);
    }

    /*
        unpause

        DISABLED. Reason: reduce contract size
    */
    function unpause() public override {
        require(false);
    }
}
