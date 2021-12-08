//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./ERC721/ERC721.sol";
import "./ERC20/IERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/String.sol";
import "./lib/Util.sol";
import "./lib/SafeERC20.sol";
import "./Member.sol";
interface INFT{
    function transferFrom(address _from,address _to,uint256 _tokenId)external;
    function approve(address _approved,uint256 _tokenId) external;
    function safeTransferFrom(address _from,address _to,uint256 _tokenId) external;
    function viewTokenID() view external returns(uint256);
    function setTokenTypeAttributes(uint256 _tokenId,uint8 _typeAttributes,uint256 _tvalue) external;
    function transferList(address _to,uint256[] calldata _tokenIdList) external;
    function ownerOf(uint256 _tokenID) external returns (address _owner);
    function starAttributes(uint256 _tokenID) external view returns(address,string memory,uint256,uint256,uint256,bool);
    function safeBatchTransferFrom(address from, address to,uint256[] memory tokenIds) external; 
    function burn(uint256 Id) external;
    function changePower(uint256 tokenId,uint256 power)external returns(bool);
}

interface IPromote{
    function update(uint256 amount) external;
}

interface IUniswapV2Pair {
    function balanceOf(address owner) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract REAUpdateCard is ERC721,Member {
    using String for string;
	using SafeERC20 for IERC20;
	using SafeMath for uint256;
    

 
    uint256 public card_Id = 0;
    INFT nft;
    IERC20 public usdt;
    IERC20 public era;
    IUniswapV2Pair public pair;
    uint256[] public cardPowerPrice = [525,1050,2100,4200,8400];

    mapping(uint256 => CardAttributesStruct) public cardAttributes;
    mapping(uint256 => mapping(uint256 => CardUpdateRecord)) public updateRecord;


    event Mintcard(address indexed owner,uint256 grade, uint256 id, uint256 amount);
    event Update(address indexed user,uint256 nftId,uint256 grade,uint256 time); 

    struct CardAttributesStruct{

      uint256 grade;  //等级
    }


    struct CardUpdateRecord{
        address user;
        uint256 timeStamp;
    }

    
    constructor(INFT _nft,IERC20 _usdt, IERC20 _era, IUniswapV2Pair _pair)
        ERC721("UPdate Token", "REAUPDATE") {
            nft = _nft;
            usdt = _usdt;
            era = _era;
            pair = _pair;
    }

    function transfer(address to,uint256 tokenId) external payable returns(bool) {               //updateCard转账
        _transferFrom(msg.sender, to, tokenId);
        return true;
    }

    
    function mintCard(uint256 grade) public {
            require(grade >= 2 && grade <= 6,"Wrong grade!");
            address user = msg.sender;
            uint256 era_price = getPrice();
            uint256 needPay = cardPowerPrice[grade-2].mul(1e36).div(era_price);
            IERC20(era).transferFrom(user,address(this),needPay);
            distribute(needPay);

            card_Id++;
            cardAttributes[card_Id].grade = grade;
            _mint(user, card_Id);
            emit Mintcard(user,grade,card_Id, needPay);
    }

    function updateNFT(uint256 nftId,uint256 cardId) public{
        require(nftId <= 87600, "Only offcial NFT can update!");
        require(nft.ownerOf(nftId) == msg.sender,"It's not your nft");
        (,,uint256 nftGrade,,,) = nft.starAttributes(nftId);
        uint256 grade = cardAttributes[cardId].grade;
        require(nftGrade + 1 == grade,"Grade Mismatch");
        require(tokenOwners[cardId] == msg.sender, "It's not your cardnft");
        burn(cardId);
        delete cardAttributes[cardId];
        bool res = nft.changePower(nftId, grade);
        updateRecord[nftId][grade].user = msg.sender;
        updateRecord[nftId][grade].timeStamp = block.timestamp;
        require(res == true, "update fail");
        emit Update(msg.sender,nftId, grade,block.timestamp);
    }
    
    
    function burn(uint256 Id) public {
        address owner = tokenOwners[Id];
        require(msg.sender == owner
            || msg.sender == tokenApprovals[Id]
            || approvalForAlls[owner][msg.sender],
            "msg.sender must be owner or approved");
        
        _burn(Id);
    }



    function distribute(uint256 needpay) internal{
        
        uint256 OfficialAmount = needpay.mul(1).div(21); 
        uint256 Remaining = needpay.sub(OfficialAmount);
        uint256 burnAmount = Remaining.mul(4).div(5);
        uint256 PromoteAmount = Remaining.sub(burnAmount);
     
        IERC20(era).transfer(address(manager.members("OfficialAddress")),OfficialAmount);           //官方地址
        IERC20(era).transfer(address(manager.members("PromoteAddress")),PromoteAmount);               //推广奖励地址
        IPromote(manager.members("PromoteAddress")).update(PromoteAmount);
        IERC20(era).burn(burnAmount); 
        
    }

    
    function tokenURI(uint256 NftId) external view override returns(string memory) {
        bytes memory bs = abi.encodePacked(NftId);
        return uriPrefix.concat("nft/").concat(Util.base64Encode(bs));
    }
    
    function setUriPrefix(string memory prefix)  
        external  {
        require(msg.sender == manager.members("owner"));
        uriPrefix = prefix;
    }


    function getPrice() public view returns(uint256){
        uint256 usd_balance;
        uint256 era_balance;
        if (pair.token0() == address(usdt)) {
          (usd_balance, era_balance , ) = pair.getReserves();   
        }  
        else{
          (era_balance, usd_balance , ) = pair.getReserves();           
        }
        uint256 token_price = usd_balance.mul(1e18).div(era_balance);
        return token_price;
    }


    function getUpdateRecord(uint256 tokenId) public view returns(CardUpdateRecord[] memory){
        (,,uint256 Grade,,,) = nft.starAttributes(tokenId);
        require(Grade >= 2,"No upgrade record!");
        CardUpdateRecord[] memory record;
        for(uint256 i = 2;i<=Grade;i++){
            record[i] = updateRecord[tokenId][i];
        }
        return record;

    }

}