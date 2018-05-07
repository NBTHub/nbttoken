pragma solidity ^0.4.17;
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/ownership/rbac/RBACWithAdmin.sol';

contract NbtToken is StandardToken, Ownable, RBACWithAdmin {

    /*** EVENTS ***/

    event ExchangeableTokensInc(address indexed from, uint256 amount);
    event ExchangeableTokensDec(address indexed to, uint256 amount);

    event CirculatingTokensInc(address indexed from, uint256 amount);
    event CirculatingTokensDec(address indexed to, uint256 amount);

    event SaleableTokensInc(address indexed from, uint256 amount);
    event SaleableTokensDec(address indexed to, uint256 amount);

    event StockTokensInc(address indexed from, uint256 amount);
    event StockTokensDec(address indexed to, uint256 amount);

    event BbAddressUpdated(address indexed ethereum_address, string bb_address);

    /*** CONSTANTS ***/

    string public name = 'NiceBytes';
    string public symbol = 'NBT';

    uint256 public decimals = 8;

    uint256 public INITIAL_SUPPLY = 10000000000 * 10**decimals; // One time total supply
    uint256 public AIRDROP_START_AT = 1525780800; // May 8, 12:00 UTC
    uint256 public AIRDROPS_COUNT = 82;
    uint256 public AIRDROPS_PERIOD = 86400;
    uint256 public CIRCULATING_BASE = 2000000000 * 10**decimals;
    uint256 public MAX_AIRDROP_VOLUME = 2; // %
    uint256 public INITIAL_EXCHANGEABLE_TOKENS_VOLUME = 1200000000 * 10**decimals;
    uint256 public MAX_AIRDROP_TOKENS = 8000000000 * 10**decimals; // 8 billions
    uint256 public MAX_SALE_VOLUME = 800000000 * 10**decimals;
    uint256 public EXCHANGE_COMMISSION = 200 * 10**decimals; // NBT
    uint256 public MIN_TOKENS_TO_EXCHANGE = 1000 * 10**decimals; // should be bigger than EXCHANGE_COMMISSION
    uint256 public EXCHANGE_RATE = 1000;
    string constant ROLE_EXCHANGER = "exchanger";


    /*** STORAGE ***/

    uint256 public exchangeableTokens;
    uint256 public exchangeableTokensFromSale;
    uint256 public exchangeableTokensFromStock;
    uint256 public circulatingTokens;
    uint256 public circulatingTokensFromSale;
    uint256 public saleableTokens;
    uint256 public stockTokens;
    address public crowdsale;
    address public exchange_commission_wallet;

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
            address(msg.sender) == address(crowdsale)
        );
        _;
    }

    /*** CONSTRUCTOR ***/

    function NbtToken() public {
        totalSupply_ = INITIAL_SUPPLY;
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
        uint256 _volume = INITIAL_EXCHANGEABLE_TOKENS_VOLUME;
        uint256 _airdrops = 0;

        if (now > AIRDROP_START_AT) {
            _airdrops = (now.sub(AIRDROP_START_AT)).div(AIRDROPS_PERIOD);
            _airdrops = _airdrops.add(1);
        }

        if (_airdrops > AIRDROPS_COUNT) {
            _airdrops = AIRDROPS_COUNT;
        }

        uint256 _from_airdrops = 0;
        uint256 _base = CIRCULATING_BASE;
        for (uint256 i = 1; i <= _airdrops; i++) {
            _from_airdrops = _from_airdrops.add(_base.mul(MAX_AIRDROP_VOLUME).div(100));
            _base = _base.add(_base.mul(MAX_AIRDROP_VOLUME).div(100));
        }
        if (_from_airdrops > MAX_AIRDROP_TOKENS) {
            _from_airdrops = MAX_AIRDROP_TOKENS;
        }

        _volume = _volume.add(_from_airdrops);

        return _volume;
    }

    /*** setters  ***/

    function setBbAddress(string _bbAddress) public returns (bool) {
        bbAddresses[msg.sender] = _bbAddress;
        emit BbAddressUpdated(msg.sender, _bbAddress);
        return true;
    }

    function setCrowdsaleAddress(address _addr) onlyAdmin public returns (bool) {
        require(_addr != address(0) && _addr != address(this));
        crowdsale = _addr;
        return true;
    }

    function setExchangeCommissionAddress(address _addr) onlyAdmin public returns (bool) {
        require(_addr != address(0) && _addr != address(this));
        exchange_commission_wallet = _addr;
        return true;
    }

    /*** sale methods  ***/

    // For balancing of the sale limit between two networks
    function moveTokensFromSaleToExchange(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(_amount <= balances[crowdsale]);
        balances[crowdsale] = balances[crowdsale].sub(_amount);
        saleableTokens = saleableTokens.sub(_amount);
        exchangeableTokensFromSale = exchangeableTokensFromSale.add(_amount);
        balances[address(this)] = balances[address(this)].add(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        emit SaleableTokensDec(address(this), _amount);
        emit ExchangeableTokensInc(address(crowdsale), _amount);
        return true;
    }

    function moveTokensFromSaleToCirculating(address _to, uint256 _amount) onlyCrowdsale public returns (bool) {
        saleableTokens = saleableTokens.sub(_amount);
        circulatingTokensFromSale = circulatingTokensFromSale.add(_amount) ;
        circulatingTokens = circulatingTokens.add(_amount) ;
        emit SaleableTokensDec(_to, _amount);
        emit CirculatingTokensInc(address(crowdsale), _amount);
        return true;
    }

    /*** stock methods  ***/

    function moveTokensFromStockToExchange(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(_amount <= stockTokens);
        require(exchangeableTokensFromStock + _amount <= howMuchTokensAvailableForExchangeFromStock());
        stockTokens = stockTokens.sub(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        exchangeableTokensFromStock = exchangeableTokensFromStock.add(_amount);
        emit StockTokensDec(address(this), _amount);
        emit ExchangeableTokensInc(address(this), _amount);
        return true;
    }

    function moveTokensFromStockToSale(uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(crowdsale != address(0) && crowdsale != address(this));
        require(_amount <= stockTokens);
        require(_amount + exchangeableTokensFromSale + saleableTokens + circulatingTokensFromSale <= MAX_SALE_VOLUME);

        stockTokens = stockTokens.sub(_amount);
        saleableTokens = saleableTokens.add(_amount);
        balances[address(this)] = balances[address(this)].sub(_amount);
        balances[crowdsale] = balances[crowdsale].add(_amount);

        emit Transfer(address(this), crowdsale, _amount);
        emit StockTokensDec(address(crowdsale), _amount);
        emit SaleableTokensInc(address(this), _amount);
        return true;
    }

    /*** exchange methods  ***/

    function getTokensFromExchange(address _to, uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require(_amount <= exchangeableTokens);
        require(_amount <= balances[address(this)]);

        exchangeableTokens = exchangeableTokens.sub(_amount);
        circulatingTokens = circulatingTokens.add(_amount);

        balances[address(this)] = balances[address(this)].sub(_amount);
        balances[_to] = balances[_to].add(_amount);

        emit Transfer(address(this), _to, _amount);
        emit ExchangeableTokensDec(_to, _amount);
        emit CirculatingTokensInc(address(this), _amount);
        return true;
    }

    function sendTokensToExchange(uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        require(_amount >= MIN_TOKENS_TO_EXCHANGE);
        require(!stringsEqual(bbAddresses[msg.sender], ''));
        require(exchange_commission_wallet != address(0) && exchange_commission_wallet != address(this));

        balances[msg.sender] = balances[msg.sender].sub(_amount); // ! before sub(_commission)

        uint256 _commission = EXCHANGE_COMMISSION + _amount % EXCHANGE_RATE;
        _amount = _amount.sub(_commission);

        circulatingTokens = circulatingTokens.sub(_amount);
        exchangeableTokens = exchangeableTokens.add(_amount);
        exchangeBalances[msg.sender] = exchangeBalances[msg.sender].add(_amount);

        balances[address(this)] = balances[address(this)].add(_amount);
        balances[exchange_commission_wallet] = balances[exchange_commission_wallet].add(_commission);

        emit Transfer(msg.sender, address(exchange_commission_wallet), _commission);
        emit Transfer(msg.sender, address(this), _amount);
        emit CirculatingTokensDec(address(this), _amount);
        emit ExchangeableTokensInc(msg.sender, _amount);
        return true;
    }

    function exchangeBalanceOf(address _addr) public view returns (uint256 _tokens) {
        return exchangeBalances[_addr];
    }

    function decExchangeBalanceOf(address _addr, uint256 _amount) onlyAdminOrExchanger public returns (bool) {
        require (exchangeBalances[_addr] > 0);
        require (exchangeBalances[_addr] >= _amount);
        exchangeBalances[_addr] = exchangeBalances[_addr].sub(_amount);
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
