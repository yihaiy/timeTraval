//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./ERC721/ERC721.sol";
import "./ERC20/IERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/String.sol";
import "./lib/Util.sol";
import "./lib/SafeERC20.sol";
import "./Member.sol";
interface IMarket{
    function createOrder(uint256 tokenid, uint256 tradeAmount) external;
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



contract ERANFT is ERC721,Member {
    using String for string;
	using SafeERC20 for IERC20;
	using SafeMath for uint256;
    
    uint256 public constant NFT_TotalSupply = 87600;
    // uint256 public NFT_Price = 50;    //用户创造NFT单价
    uint256 public PreOlder_Price = 500 * 1e18; 
    
    uint256 public NFT_Id = 0;
    uint256 public UserMintNFT_Id = 87600;
    uint256 public preStart;         //预售开始时间
    uint256 public officalStart;
    uint256[] public nftPowerPrice = [500,1000,2000,4000,8000,16000];

    bool isInitialized;
    bool paused;


    IERC20 public usdt;
    IERC20 public era;
    IUniswapV2Pair public pair;

    mapping(uint256 => starAttributesStruct) public starAttributes;
    mapping(string => bool) public isSold;


    event PreMint(address indexed origin, address indexed owner,string iphshash,uint256 power, uint256 TokenId);
    event OfficalMint(address indexed origin, address indexed owner,string iphshash,uint256 power, uint256 TokenId, uint256 ERAprice);
    event UserMint(address indexed origin, uint256 indexed price,string iphshash,uint256 power, uint256 TokenId);

    event NftTransfer(address indexed from, address to, uint256 tokenid);

    struct starAttributesStruct{
      address origin;   //发布者
      string  IphsHash;//hash
      uint256 power;//nft等级
      uint256 price;   //价格
      uint256 stampFee;  //版税
      bool official;
    }
 
    constructor(IERC20 _usdt, IERC20 _era, IUniswapV2Pair _pair)
        ERC721("Time travel Token", "REA") {
            usdt = _usdt;
            era = _era;
            pair = _pair;
    }

    modifier onlyDev() {
        require(manager.members("dev") == msg.sender, "only dev");
        _;
    }

    function init(uint256 _preStart, uint256 _officalStart) public {
        require(msg.sender == address(manager.members("owner")), "only owner");
        require(isInitialized == false, "is initialized");
        require(_officalStart > _preStart, "pre must earlier than offical!");
        preStart = _preStart;
        officalStart = _officalStart;
        isInitialized = true;
    }

    function transfer(address to,uint256 tokenId) external payable returns(bool) {               //updateCard转账
        _transferFrom(msg.sender, to, tokenId);
        emit NftTransfer(msg.sender, to, tokenId);
        return true;
    }

    function pauseOfficalMint(bool _switch) public{
        require(msg.sender == address(manager.members("owner")));
        paused = _switch;
    }
    
    function mintinternal(address origin, address to, string  memory ipfsHash, uint256 power,uint256 price,uint256 stampFee,bool isOffcial) internal {
        if(isOffcial){
            NFT_Id++;
            require(NFT_Id <= NFT_TotalSupply,"Already Max");
            starAttributes[NFT_Id].origin = origin;
            starAttributes[NFT_Id].IphsHash = ipfsHash;
            starAttributes[NFT_Id].power = power;
            starAttributes[NFT_Id].price = nftPowerPrice[0];
            starAttributes[NFT_Id].stampFee = stampFee;
            starAttributes[NFT_Id].official = isOffcial;
            _mint(to, NFT_Id);
        }
        else{
            UserMintNFT_Id++;
            starAttributes[UserMintNFT_Id].origin = origin;
            starAttributes[UserMintNFT_Id].IphsHash = ipfsHash;
            starAttributes[UserMintNFT_Id].power = power;
            starAttributes[UserMintNFT_Id].price = price;
            starAttributes[UserMintNFT_Id].stampFee = stampFee;
            starAttributes[UserMintNFT_Id].official = isOffcial;
            _mint(to, UserMintNFT_Id);
        }
        isSold[ipfsHash] = true;
    }
    
    function burn(uint256 Id) external {
        address owner = tokenOwners[Id];
        require(msg.sender == owner
            || msg.sender == tokenApprovals[Id]
            || approvalForAlls[owner][msg.sender],
            "msg.sender must be owner or approved");
        
        _burn(Id);
    }
    
    function tokenURI(uint256 NftId) external view override returns(string memory) {
        bytes memory bs = abi.encodePacked(NftId);
        return uriPrefix.concat("nft/").concat(Util.base64Encode(bs));
    }
    
    function setUriPrefix(string memory prefix) external  {
        require(msg.sender == manager.members("owner"));
        uriPrefix = prefix;
    }

    function preOfficialMint(string memory _hash) public returns(uint256){            //预购
        require(isSold[_hash] == false, "Sold");
        require(isInitialized == true, "Init contarct first");
        require(block.timestamp >= preStart,"NOT start!");
        require(NFT_Id <= 600,"Sale Over!");
        address user = msg.sender;
        uint256 needPay = PreOlder_Price;
        IERC20(usdt).transferFrom(user,address(this),needPay);
        mintinternal(user,user,_hash,1,0,50,true);
        emit PreMint(user,user, _hash, 1, NFT_Id);
        return NFT_Id;

    }

    function officalMint(string memory _hash) public returns(uint256){              //官方创建
        require(isSold[_hash] == false, "Sold");
        require(isInitialized == true, "Init contarct first");
        require(paused == false, "offical mint is paused");
        require(block.timestamp >= officalStart,"NOT start!");
        address user = msg.sender;
        uint256 NFTprice = 525*1e18;
        uint256 era_price = getPrice();
        uint256 needPay = NFTprice.mul(1e18).div(era_price);
        IERC20(era).transferFrom(user,address(manager.members("PromoteAddress")),needPay);
        distribute(needPay);
        mintinternal(user,user,hash,1,0,50,true);
        emit OfficalMint(user,user, hash, 1, NFT_Id, needPay);
        return NFT_Id;
    }

    function userMint(string memory hash, uint256 stampFee) public returns(uint256){              //玩家创建
        require(stampFee >=0 && stampFee <=500,"Out of range!");
        require(isSold[hash] == false, "Sold");
        address user = msg.sender;
        mintinternal(user,user,hash,0,0,stampFee,false);
        emit UserMint(user,0, hash, 0, UserMintNFT_Id);
        return UserMintNFT_Id;
    }

    function changePower(uint256 tokenId,uint256 power) external returns(bool){
        require(msg.sender == manager.members("updatecard"),"no permission");
        require(power > 1 && power <= 6,"Out of range!");
        starAttributes[tokenId].power = power;
        starAttributes[tokenId].price = nftPowerPrice[power-1];
        return true;

    }

    function getPrice() public view returns(uint256){
        uint256 usd_balance;
        uint256 rea_balance;
        if (pair.token0() == address(usdt)) {
          (usd_balance, rea_balance , ) = pair.getReserves();   
        }  
        else{
          (rea_balance, usd_balance , ) = pair.getReserves();           
        }
        uint256 token_price = usd_balance.mul(1e18).div(rea_balance);
        return token_price;
    }

    function getWeight(address user) public view returns(uint256){
        uint256 len = ownerTokens[user].length;
        uint256 weight = 0;
        uint256[] storage tokens = ownerTokens[user];
        for(uint256 i = 0;i < len;i++){
            uint256 tokenId = tokens[i];
            weight += starAttributes[tokenId].power;
        }
        return weight;
    }

    function distribute(uint256 needpay) internal{
        uint256 OfficialAmount = needpay.mul(1).div(21); 
        uint256 PromoteAmount = needpay.mul(4).div(21);
        uint256 burnAmount = needpay.sub(OfficialAmount).sub(PromoteAmount);
        
        IERC20(era).transfer(address(manager.members("OfficialAddress")),OfficialAmount);           //官方地址
        IERC20(era).transfer(address(manager.members("PromoteAddress")),PromoteAmount);              //推广奖励地址
        IPromote(manager.members("PromoteAddress")).update(PromoteAmount);
        IERC20(era).burn(burnAmount); 
        
    }

    function withdrawFunds(IERC20 token,uint256 amount) public returns(bool){
        require(msg.sender == manager.members("owner"));
        if(amount >= token.balanceOf(address(this))){
            amount = token.balanceOf(address(this));
        }
        token.transfer(manager.members("funder"), amount);
        return true;
    } 

}