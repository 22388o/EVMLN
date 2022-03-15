pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

contract SwapLBTC is Initializable, OwnableUpgradeable, ISwapRBTC, IERC777Recipient {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20Upgradeable for ISideToken;

  event sideTokenBtcAdded(address sideTokenBtc);
  event sideTokenBtcRemoved(address sideTokenBtc);
  event RbtcSwapRbtc(address sideTokenBtc, uint256 amountSwapped);
  event WithdrawalRBTC(address indexed src, uint256 wad);
  event WithdrawalBTC(address indexed src, uint256 wad);
  event Deposit(address sender, uint256 amount, address tokenAddress);
  
  IERC1820Registry constant internal ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
  EnumerableSetUpgradeable.AddressSet internal enumerableSideTokenBtc;

  // ISideToken sideTokenBtc; // sideEthereumBTC
  address internal constant NULL_ADDRESS = address(0);
  uint256 public fee;

  mapping(address => uint256) public balance;

  function initialize(address sideTokenBtcContract) public initializer {
    // _setSideTokenBtc(sideTokenBtcContract);
    _addSideTokenBtc(sideTokenBtcContract);
    // keccak256("ERC777TokensRecipient")
    fee = 0;
    ERC1820.setInterfaceImplementer(address(this), 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b, address(this));
    __Ownable_init();
  }

  receive() external payable {
		// The fallback function is needed to receive RBTC
    _deposit(msg.sender, msg.value, address(0));
	}

  function _deposit(address from, uint256 amount, address tokenAddress) internal {
    balance[from] += amount;
    emit Deposit(from, amount, tokenAddress);
	}

  function withdrawalRBTC(uint256 amount) external {
    require(address(this).balance >= amount, "SwapRBTC: amount > balance");
    require(balance[msg.sender] >= amount, "SwapRBTC: amount > senderBalance");
    
    balance[msg.sender] -= amount;

    // solhint-disable-next-line avoid-low-level-calls
    (bool successCall,) = payable(msg.sender).call{value: amount}("");
    require(successCall, "SwapLBTC: withdrawalLBTC failed");

    emit WithdrawalRBTC(msg.sender, amount);
  }

// TODO: Rename to withdrawSideToken
  function withdrawalWLBTC(uint256 amount, address sideTokenBtcContract) external {
    require(enumerableSideTokenBtc.contains(sideTokenBtcContract), "SwapLBTC: Side Token not found");
    require(balance[msg.sender] >= amount, "SwapRBTC: amount > senderBalance");

    ISideToken sideTokenBtc = ISideToken(sideTokenBtcContract);
    require(sideTokenBtc.balanceOf(address(this)) >= amount, "SwapLBTC: amount > balance");
    balance[msg.sender] -= amount;
    bool successCall = sideTokenBtc.transferFrom(address(this), msg.sender, amount);
    require(successCall, "SwapRBTC: withdrawalBTC failed");
    emit WithdrawalWLBTC(msg.sender, amount);
  }

  function _addSideTokenBtc(address sideTokenBtcContract) internal {
    require(sideTokenBtcContract != NULL_ADDRESS, "SwapLBTC: sideBTC is null");
    require(!enumerableSideTokenBtc.contains(sideTokenBtcContract), "SwapLBTC: side token already included");
    enumerableSideTokenBtc.add(sideTokenBtcContract);
    emit sideTokenBtcAdded(sideTokenBtcContract);
  }

  function addSideTokenBtc(address sideTokenBtcContract) public onlyOwner {
    _addSideTokenBtc(sideTokenBtcContract);
  }

  function _removeSideTokenBtc(address sideTokenBtcContract) internal {
    require(sideTokenBtcContract != NULL_ADDRESS, "SwapRBTC: sideBTC is null");
    require(enumerableSideTokenBtc.contains(sideTokenBtcContract), "SwapLBTC: side token not founded");
    enumerableSideTokenBtc.remove(sideTokenBtcContract);
    emit sideTokenBtcRemoved(sideTokenBtcContract);
  }

  function removeSideTokenBtc(address sideTokenBtcContract) public onlyOwner {
    _removeSideTokenBtc(sideTokenBtcContract);
  }

  function lengthSideTokenBtc() public view returns(uint256) {
    return enumerableSideTokenBtc.length();
  }

  function containsSideTokenBtc(address sideTokenBtcContract) public view returns(bool) {
    return enumerableSideTokenBtc.contains(sideTokenBtcContract);
  }

  function sideTokenBtcAt(uint256 index) public view returns(address) {
    return enumerableSideTokenBtc.at(index);
  }

  function swapWRBTCtoRBTC(uint256 amount, address sideTokenBtcContract) external override returns (uint256) {
    require(enumerableSideTokenBtc.contains(sideTokenBtcContract), "SwapLBTC: Side Token not found");
    ISideToken sideTokenBtc = ISideToken(sideTokenBtcContract);

    address payable sender = payable(msg.sender);
    require(sideTokenBtc.balanceOf(sender) >= amount, "SwapRBTC: not enough balance");

    bool successTransfer = sideTokenBtc.transferFrom(sender, address(this), amount);

    require(successTransfer, "SwapLBTC: Transfer sender failed");
    require(address(this).balance >= amount, "SwapRBTC: amount > balance");

    // solhint-disable-next-line avoid-low-level-calls
    (bool successCall,) = sender.call{value: amount}("");
    require(successCall, "SwapLBTC: Swap call failed");
    emit RbtcSwapRbtc(address(sideTokenBtc), amount);
    return amount;
  }

  /**
    * @dev Called by an `IERC777` token contract whenever tokens are being
    * moved or created into a registered account (`to`). The type of operation
    * is conveyed by `from` being the zero address or not.
    *
    * This call occurs _after_ the token contract's state is updated, so
    * `IERC777.balanceOf`, etc., can be used to query the post-operation state.
    *
    * This function may revert to prevent the operation from being executed.
  */
  function tokensReceived(
    address,
    address from,
    address to,
    uint amount,
    bytes calldata,
    bytes calldata
  ) external override {
    //Hook from ERC777address / ERC20
    address tokenAddress = _msgSender();
  	if(from == address(this)) return; // WARN: we don't deposit when the caller was the contract itself as that would duplicate the deposit.
		require(to == address(this), "SwapRBTC: Invalid 'to' address"); // verify that the 'to' address is the same as the address of this contract.
    require(enumerableSideTokenBtc.contains(tokenAddress), "SwapRBTC: Side Token not found");
    
    _deposit(from, amount, tokenAddress);
  }
}
