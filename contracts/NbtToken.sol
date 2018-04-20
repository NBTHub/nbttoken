pragma solidity ^0.4.17;
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/ownership/rbac/RBAC.sol';

contract NbtToken is StandardToken, Ownable, RBAC {

    /*** EVENTS ***/

    event ExchangeableTokensInc(address indexed from, uint256 amount);
    event ExchangeableTokensDec(address indexed to, uint256 amount);

    event OnHandTokensInc(address indexed from, uint256 amount);
    event OnHandTokensDec(address indexed to, uint256 amount);

    event SaleableTokensInc(address indexed from, uint256 amount);
    event SaleableTokensDec(address indexed to, uint256 amount);

    event StockTokensInc(address indexed from, uint256 amount);
    event StockTokensDec(address indexed to, uint256 amount);

    event BbAddressUpdated(address indexed ethereum_address, string bb_address);

    /*** CONSTANTS ***/

    string public name = 'NBT';
    string public symbol = 'NBT';

    uint256 public decimals = 8;

    uint256 public INITIAL_SUPPLY = 10000000000 * 10**decimals; // One time total supply
    uint256 public AIRDROP_START_AT = 1524209178;
    uint256 public AIRDROPS_COUNT = 50;
    uint256 public AIRDROPS_PERIOD = 86400;
    uint256 public MAX_AIRDROP_VOLUME = 16000000 * 10**decimals;
    uint256 public INITIAL_AIRDROP_VOLUME = 300000000 * 10**decimals;
    uint256 public MAX_SALE_VOLUME = 800000000 * 10**decimals;
    uint256 public EXCHANGE_COMMISSION = 2 * 10**decimals; // ABC
    uint256 public MIN_TOKENS_TO_EXCHANGE = 10 * 10**decimals; // should be bigger than EXCHANGE_COMMISSION
    uint256 public EXCHANGE_RATE = 1000;

    address public EXCHANGE_COMMISSION_WALLET = 0x0;

    string constant ROLE_EXCHANGER = "exchanger";


    /*** STORAGE ***/

    uint256 public exchangeableTokens;
    uint256 public exchangeableTokensFromSale;
    uint256 public onHandTokens;
    uint256 public onHandTokensFromSale;
    uint256 public saleableTokens;
    uint256 public stockTokens;
    address public crowdsale;

    mapping(address => uint256) exchangeBalances;
    mapping(address => string) bbAddresses;

    /*** MODIFIERS ***/

    modifier onlyAdminOrExchanger()
    {
        require(
            hasRole(msg.sender, ROLE_ADMIN) ||
            hasRole(msg.sender, ROLE_EXCHANGER)
        );
        _;
    }

    modifier onlyCrowdsale()
    {
        require(
            msg.sender == crowdsale
        );
        _;
    }

    /*** CONSTRUCTOR ***/

    function NbtToken() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[this] = INITIAL_SUPPLY;
        balances[this] = INITIAL_SUPPLY;
        stockTokens = INITIAL_SUPPLY;
        emit StockTokensInc(address(0), INITIAL_SUPPLY);
        addRole(msg.sender, ROLE_EXCHANGER);
    }

    /*** PUBLIC AND EXTERNAL FUNCTIONS ***/

    /*** getters  ***/
    
    function getBbAddress(address _addr) public view returns (string _bbAddress) {
        return bbAddresses[_addr];
    }

    function howMuchTokensAvailableForExchangeFromStock() public view returns (uint256) {
        uint256 _volume = INITIAL_AIRDROP_VOLUME;
        _volume = _volume.add( MAX_AIRDROP_VOLUME.mul((now - AIRDROP_START_AT) / AIRDROPS_PERIOD + 1));
        return _volume;
    }

    /*** setters  ***/

    function setBbAddress(string _bbAddress) public returns (bool) {
        bbAddresses[msg.sender] = _bbAddress;
        emit BbAddressUpdated(msg.sender, _bbAddress);
        return true;
    }

    function setCrowdsaleAddress(address _addr) public returns (bool) {
        crowdsale = _addr;
        return true;
    }

    /*** sale methods  ***/

    // For balancing of the sale limit between two networks
    function moveTokensFromSaleToExchange(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(_amount <= balances[crowdsale]);
        exchangeableTokensFromSale = exchangeableTokensFromSale.add(_amount);
        balances[crowdsale] = balances[crowdsale].sub(_amount);
        saleableTokens = saleableTokens.sub(_amount);
        onHandTokens = onHandTokens.add(_amount);
        emit SaleableTokensDec(address(this), _amount);
        emit OnHandTokensInc(address(crowdsale), _amount);
        return true;
    }

    function moveTokensFromSaleToOnHand(address _to, uint256 _amount) onlyCrowdsale public returns (bool) {
        onHandTokensFromSale = onHandTokensFromSale.add(_amount) ;
        saleableTokens = saleableTokens.sub(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        emit SaleableTokensDec(_to, _amount);
        emit OnHandTokensInc(address(crowdsale), _amount);
        return true;
    }

    /*** stock methods  ***/

    function moveTokensFromStockToExchange(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(_amount <= stockTokens);
        require(exchangeableTokens + _amount - exchangeableTokensFromSale <= howMuchTokensAvailableForExchangeFromStock());
        stockTokens = stockTokens.sub(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        emit StockTokensDec(address(this), _amount);
        emit ExchangeableTokensInc(address(this), _amount);
        return true;
    }

    function moveTokensFromStockToSale(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(crowdsale != address(0) && crowdsale != address(this));
        require(_amount <= stockTokens);
        require(_amount + exchangeableTokensFromSale + saleableTokens + onHandTokensFromSale <= MAX_SALE_VOLUME);
        stockTokens = stockTokens.sub(_amount);
        saleableTokens = saleableTokens.add(_amount);
        balances[crowdsale] = balances[crowdsale].add(_amount);
        emit Transfer(address(this), crowdsale, _amount);
        emit StockTokensDec(address(crowdsale), _amount);
        emit SaleableTokensInc(address(this), _amount);
        return true;
    }

    /*** exchange methods  ***/

    function getTokensFromExchange(address _to, uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(address(this), _to, _amount);
        emit ExchangeableTokensDec(_to, _amount);
        emit OnHandTokensInc(address(this), _amount);
        return true;
    }

    function sendTokensToExchange(uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        require(_amount >= MIN_TOKENS_TO_EXCHANGE);
        require(!stringsEqual(bbAddresses[msg.sender], ''));
        uint256 _commission = EXCHANGE_COMMISSION + _amount % EXCHANGE_RATE;
        _amount = _amount.sub(_commission);

        onHandTokens = onHandTokens.sub(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        exchangeBalances[msg.sender] = exchangeBalances[msg.sender].add(_amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[EXCHANGE_COMMISSION_WALLET] = balances[msg.sender].add(_commission);
        emit Transfer(msg.sender, address(EXCHANGE_COMMISSION_WALLET), _commission);
        emit Transfer(msg.sender, address(this), _amount);
        emit OnHandTokensDec(address(this), _amount);
        emit ExchangeableTokensInc(msg.sender, _amount);
        return true;
    }

    function exchangeBalanceOf(address _addr) public view returns (uint256 _tokens) {
        return exchangeBalances[_addr];
    }

    function nullExchangeBalanceOf(address _addr) onlyAdminOrExchanger public returns (bool) {
        require (exchangeBalances[_addr] > 0);
        exchangeBalances[_addr] = 0;
        return true;
    }
    
    /*** INTERNAL FUNCTIONS ***/

    function stringsEqual(string storage _a, string memory _b) internal view returns (bool) {
        bytes storage a = bytes(_a);
        bytes memory b = bytes(_b);
        if (a.length != b.length)
            return false;
        for (uint256 i = 0; i < a.length; i ++)
            if (a[i] != b[i])
                return false;
        return true;
    }
}
