pragma solidity ^0.4.17;
import 'zeppelin-solidity/contracts/crowdsale/Crowdsale.sol';
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'zeppelin-solidity/contracts/ownership/rbac/RBACWithAdmin.sol';

// NbtToken crowdsale-valuable interface
contract NbtToken  {
    uint256 public saleableTokens;
    uint256 public MAX_SALE_VOLUME;
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function moveTokensFromSaleToCirculating(address _to, uint256 _amount) public returns (bool);
}

// Main crowdsale contract
contract NbtCrowdsale is Crowdsale, Pausable, RBACWithAdmin {

    /*** EVENTS ***/

    event NewStart(uint256 start);
    event NewDeadline(uint256 deadline);
    event NewRate(uint256 rate);
    event NewWallet(address new_address);
    event Sale(address indexed buyer, uint256 tokens_with_bonuses);

    /*** CONSTANTS ***/

    uint256 public DECIMALS = 8;
    uint256 public BONUS1 = 100; // %
    uint256 public BONUS1_LIMIT = 150000000 * 10**DECIMALS;
    uint256 public BONUS2 = 60; // %
    uint256 public BONUS2_LIMIT = 250000000 * 10**DECIMALS;
    uint256 public MIN_TOKENS = 1000 * 10**DECIMALS;

    NbtToken public token;

    /*** STORAGE ***/

    uint256 public start;
    uint256 public deadline;
    bool crowdsaleClosed = false;

    /*** MODIFIERS ***/

    modifier afterDeadline() { if (now > deadline) _; }
    modifier beforeDeadline() { if (now <= deadline) _; }
    modifier afterStart() { if (now >= start) _; }
    modifier beforeStart() { if (now < start) _; }

    /*** CONSTRUCTOR ***/
    /**
      * @param _rate Number of token units a buyer gets per wei
      * @param _wallet Address where collected funds will be forwarded to
      * @param _token Address of the token being sold
      * @param _start Start date of the crowdsale
      * @param _deadline Deadline of the crowdsale
      */
    function NbtCrowdsale(uint256 _rate, address _wallet, NbtToken _token, uint256 _start, uint256 _deadline) Crowdsale(_rate, _wallet, ERC20(_token)) public {
        require(_rate > 0);
        require(_wallet != address(0));
        require(_token != address(0));
        require(_start < _deadline);

        start = _start;
        deadline = _deadline;

        rate = _rate;
        wallet = _wallet;
        token = _token;
    }

    /*** PUBLIC AND EXTERNAL FUNCTIONS ***/

    /**
     * @dev set new start date for crowdsale.
     * @param _start The new start timestamp
     */
    function setStart(uint256 _start) onlyAdmin whenPaused public returns (bool) {
        require(_start < deadline);
        start = _start;
        emit NewStart(start);
        return true;
    }

    /**
     * @dev set new start date for crowdsale.
     * @param _deadline The new deadline timestamp
     */
    function setDeadline(uint256 _deadline) onlyAdmin whenPaused public returns (bool) {
        require(start < _deadline);
        deadline = _deadline;
        emit NewDeadline(_deadline);
        return true;
    }

    /**
     * @dev set new wallet address
     * @param _addr The new wallet address
     */
    function setWallet(address _addr) onlyAdmin public returns (bool) {
        require(_addr != address(0) && _addr != address(this));
        wallet = _addr;
        emit NewWallet(wallet);
        return true;
    }

    /**
     * @dev set new rate for crowdsale.
     * @param _rate Number of token units a buyer gets per wei
     */
    function setRate(uint256 _rate) onlyAdmin public returns (bool) {
        require(_rate > 0);
        rate = _rate;
        emit NewRate(rate);
        return true;
    }

    /**
      * @dev called by the admin to pause, triggers stopped state
      */
    function pause() onlyAdmin whenNotPaused public {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the admin to unpause, returns to normal state
     */
    function unpause() onlyAdmin whenPaused public {
        paused = false;
        emit Unpause();
    }

    function getCurrentBonus() public view returns (uint256) {
        if (token.MAX_SALE_VOLUME().sub(token.saleableTokens()) < BONUS1_LIMIT) {
            return BONUS1;
        } else if (token.MAX_SALE_VOLUME().sub(token.saleableTokens()) < BONUS2_LIMIT) {
            return BONUS2;
        } else {
            return 0;
        }
    }

    function getTokenAmount(uint256 _weiAmount) public view returns (uint256) {
        return _getTokenAmount(_weiAmount);
    }

    /**
     * Close the crowdsale
     */
    function closeCrowdsale() onlyAdmin afterDeadline public {
        crowdsaleClosed = true;
    }

    /*** INTERNAL FUNCTIONS ***/

    /**
       * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
       * @param _beneficiary Address performing the token purchase
       * @param _weiAmount Value in wei involved in the purchase
       */
    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) whenNotPaused afterStart beforeDeadline internal {
        require(!crowdsaleClosed);
        require(_weiAmount >= 1000000000000);
        require(_getTokenAmount(_weiAmount) <= token.balanceOf(this));
        require(_getTokenAmount(_weiAmount) >= MIN_TOKENS);
        super._preValidatePurchase(_beneficiary, _weiAmount);
    }

    /**
   * @dev Validation of an executed purchase. Observe state and use revert statements to undo rollback when valid conditions are not met.
   * @param _beneficiary Address performing the token purchase
   * @param _weiAmount Value in wei involved in the purchase
   */
    function _postValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
        // optional override
    }

    /**
      * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
      * @param _beneficiary Address performing the token purchase
      * @param _tokenAmount Number of tokens to be emitted
      */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        token.moveTokensFromSaleToCirculating(_beneficiary, _tokenAmount);
        token.transfer(_beneficiary, _tokenAmount);
        emit Sale(_beneficiary, _tokenAmount);
    }

    /**
   * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
   * @param _beneficiary Address receiving the tokens
   * @param _tokenAmount Number of tokens to be purchased
   */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        _deliverTokens(_beneficiary, _tokenAmount);
    }

    /**
   * @dev Override for extensions that require an internal state to check for validity (current user contributions, etc.)
   * @param _beneficiary Address receiving the tokens
   * @param _weiAmount Value in wei involved in the purchase
   */
    function _updatePurchasingState(address _beneficiary, uint256 _weiAmount) internal {
        // optional override
    }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 _weiAmount) internal view returns (uint256) {
        uint256 _current_bonus =  getCurrentBonus();
        if (_current_bonus == 0) {
            return _weiAmount.mul(rate).div(1000000000000); // token amount for 1 Gwei
        } else {
            return _weiAmount.mul(rate).mul(_current_bonus.add(100)).div(100).div(1000000000000); // token amount for 1 Gwei
        }
    }

    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds() internal {
        wallet.transfer(msg.value);
    }

}
