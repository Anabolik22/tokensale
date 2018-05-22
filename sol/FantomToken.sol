pragma solidity ^0.4.23;

// ----------------------------------------------------------------------------
//
// Fantom Foundation FTM token public sale contract
//
// For details, please visit: http://fantom.foundation
//
//
// written by Alex Kampa - ak@sikoba.com
//
// ----------------------------------------------------------------------------


// ----------------------------------------------------------------------------
//
// SafeMath
//
// ----------------------------------------------------------------------------

library SafeMath {

    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }

    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }

    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    
}


// ----------------------------------------------------------------------------
//
// Utils
//
// ----------------------------------------------------------------------------

contract Utils {
    
    function atNow() public view returns (uint) {
        return block.timestamp;
    }
    
}


// ----------------------------------------------------------------------------
//
// Owned
//
// ----------------------------------------------------------------------------

contract Owned {

    address public owner;
    address public newOwner;

    mapping(address => bool) public isAdmin;

    event OwnershipTransferProposed(address indexed _from, address indexed _to);
    event OwnershipTransferred(address indexed _from, address indexed _to);
    event AdminChange(address indexed _admin, bool _status);

    modifier onlyOwner {require(msg.sender == owner); _;}
    modifier onlyAdmin {require(isAdmin[msg.sender]); _;}

    constructor() public {
        owner = msg.sender;
        isAdmin[owner] = true;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0x0));
        emit OwnershipTransferProposed(owner, _newOwner);
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function addAdmin(address _a) public onlyOwner {
        require(isAdmin[_a] == false);
        isAdmin[_a] = true;
        emit AdminChange(_a, true);
    }

    function removeAdmin(address _a) public onlyOwner {
        require(isAdmin[_a] == true);
        isAdmin[_a] = false;
        emit AdminChange(_a, false);
    }

}


// ----------------------------------------------------------------------------
//
// ERC20Interface
//
// ----------------------------------------------------------------------------

contract ERC20Interface {

    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);

    function totalSupply() public view returns (uint);
    function balanceOf(address _owner) public view returns (uint balance);
    function transfer(address _to, uint _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint _value) public returns (bool success);
    function approve(address _spender, uint _value) public returns (bool success);
    function allowance(address _owner, address _spender) public view returns (uint remaining);

}


// ----------------------------------------------------------------------------
//
// ERC Token Standard #20
//
// ----------------------------------------------------------------------------

contract ERC20Token is ERC20Interface, Owned {

    using SafeMath for uint;

    uint public tokensIssuedTotal = 0;
    mapping(address => uint) balances;
    mapping(address => mapping (address => uint)) allowed;

    function totalSupply() public view returns (uint) {
        return tokensIssuedTotal;
    }

    function balanceOf(address _owner) public view returns (uint balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint _amount) public returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function approve(address _spender, uint _amount) public returns (bool success) {
        // require(balances[msg.sender] >= _amount);
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) public returns (bool success) {
        require(balances[_from] >= _amount);
        require(allowed[_from][msg.sender] >= _amount);
        balances[_from] = balances[_from].sub(_amount);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint remaining) {
        return allowed[_owner][_spender];
    }

}


// ----------------------------------------------------------------------------
//
// LockSlots
//
// ----------------------------------------------------------------------------

contract LockSlots is ERC20Token, Utils {

    using SafeMath for uint;

    uint8 public constant LOCK_SLOTS = 5;
    mapping(address => uint[LOCK_SLOTS]) public lockTerm;
    mapping(address => uint[LOCK_SLOTS]) public lockAmnt;
    mapping(address => bool) public mayHaveLockedTokens;

    event RegisteredLockedTokens(address indexed account, uint indexed idx, uint tokens, uint term);

    function registerLockedTokens(address _account, uint _tokens, uint _term) internal returns (uint idx) {
        require(_term > atNow(), "lock term must be in the future"); 

        // find a slot (clean up while doing this)
        // use either the existing slot with the exact same term,
        // of which there can be at most one, or the first empty slot
        idx = 9999;    
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        uint[LOCK_SLOTS] storage amnt = lockAmnt[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] < atNow()) {
                term[i] = 0;
                amnt[i] = 0;
                if (idx == 9999) idx = i;
            }
            if (term[i] == _term) idx = i;
        }

        // fail if no slot was found
        require(idx != 9999, "registerLockedTokens: no available slot found");

        // register locked tokens
        if (term[idx] == 0) term[idx] = _term;
        amnt[idx] = amnt[idx].add(_tokens);
        mayHaveLockedTokens[_account] = true;
        emit RegisteredLockedTokens(_account, idx, _tokens, _term);
    }

    // public view functions

    function lockedTokens(address _account) public view returns (uint) {
        if (!mayHaveLockedTokens[_account]) return 0;
        return pNumberOfLockedTokens(_account);
    }

    function unlockedTokens(address _account) public view returns (uint) {
        return balances[_account].sub(lockedTokens(_account));
    }

    function isAvailableLockSlot(address _account, uint _term) public view returns (bool) {
        if (!mayHaveLockedTokens[_account]) return true;
        if (_term < atNow()) return true;
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] < atNow() || term[i] == _term) return true;
        }
        return false;
    }

    // internal and private functions

    function unlockedTokensInternal(address _account) internal returns (uint) {
        // updates mayHaveLockedTokens if necessary
        if (!mayHaveLockedTokens[_account]) return balances[_account];
        uint locked = pNumberOfLockedTokens(_account);
        if (locked == 0) mayHaveLockedTokens[_account] = false;
        return balances[_account].sub(locked);
    }

    function pNumberOfLockedTokens(address _account) private view returns (uint locked) {
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        uint[LOCK_SLOTS] storage amnt = lockAmnt[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] >= atNow()) locked = locked.add(amnt[i]);
        }
    }

}


// ----------------------------------------------------------------------------
//
// Fantom public token sale
//
// ----------------------------------------------------------------------------

contract FantomToken is ERC20Token, LockSlots {

    // Utility variable

    uint constant E18 = 10**18;
    
    // Basic token data

    string public constant name = "Fantom Token";
    string public constant symbol = "FTM";
    uint public constant decimals = 18;

    // crowdsale parameters

    uint public constant TOKEN_TOTAL_SUPPLY = 1000000000 * E18;

    bool public tokensTradeable;

    // whitelisting

    mapping(address => bool) public whitelist;
    uint public numberWhitelisted;

    // tracking tokens minted

    mapping(address => uint) public balancesMinted;

    // migration variable

    bool public isMigrationPhaseOpen;

    // Events ---------------------------------------------

    event Whitelisted(address indexed account, uint countWhitelisted);
    event TokensMinted(uint indexed mintType, address indexed account, uint tokens, uint term);
    event TokenExchangeRequested(address indexed account, uint tokens);

    // Basic Functions ------------------------------------

    constructor() public {}

    function () public {}

    // Information functions

    function availableToMint() public view returns (uint) {
      return TOKEN_TOTAL_SUPPLY.sub(tokensIssuedTotal);
    }
    
    
    // Admin functions

    function addToWhitelist(address _account) public onlyAdmin {
        pWhitelist(_account);
    }

    function addToWhitelistMultiple(address[] _addresses) public onlyAdmin {
        for (uint i = 0; i < _addresses.length; i++) { 
            pWhitelist(_addresses[i]);
        }
    }

    function pWhitelist(address _account) internal {
        if (whitelist[_account]) return;
        whitelist[_account] = true;
        numberWhitelisted = numberWhitelisted.add(1);
        emit Whitelisted(_account, numberWhitelisted);
    }

    // Owner functions ------------------------------------

    function makeTradeable() public onlyOwner {
        tokensTradeable = true;
    }

    // Token minting (only way to issue tokens) -----------

    function mintTokens(uint _mint_type, address _account, uint _tokens) public onlyOwner {
        pMintTokens(_mint_type, _account, _tokens, 0);
    }

    function mintTokensMultiple(uint _mint_type, address[] _accounts, uint[] _tokens) public onlyOwner {
        require(_accounts.length == _tokens.length);
        for (uint i = 0; i < _accounts.length; i++) {
            pMintTokens(_mint_type, _accounts[i], _tokens[i], 0);
        }
    }

    function mintTokensLocked(uint _mint_type, address _account, uint _tokens, uint _term) public onlyOwner {
        pMintTokens(_mint_type, _account, _tokens, _term);
    }

    function mintTokensLockedMultiple(uint _mint_type, address[] _accounts, uint[] _tokens, uint[] _terms) public onlyOwner {
        require(_accounts.length == _tokens.length);
        require(_accounts.length == _terms.length);
        for (uint i = 0; i < _accounts.length; i++) {
            pMintTokens(_mint_type, _accounts[i], _tokens[i], _terms[i]);
        }
    }

    function pMintTokens(uint _mint_type, address _account, uint _tokens, uint _term) private {
        require(_account != 0x0);
        require(_tokens > 0);
        require(_tokens <= availableToMint(), "not enough tokens available to mint");
        require(_term == 0 || _term > atNow(), "either without lock term, or lock term must be in the future");

        // register locked tokens (will throw if no slot is found)
        if (_term > 0) registerLockedTokens(_account, _tokens, _term);

        // update
        balances[_account] = balances[_account].add(_tokens);
        balancesMinted[_account] = balancesMinted[_account].add(_tokens);
        tokensIssuedTotal = tokensIssuedTotal.add(_tokens);

        // log event
        emit Transfer(0x0, _account, _tokens);
        emit TokensMinted(_mint_type, _account, _tokens, _term);
    }

    // Token exchange / migration to new platform ---------

    function requestTokenExchangeAll() public {
        requestTokenExchange(balances[msg.sender]);
    }

    function requestTokenExchange(uint _tokens) public {
        require(isMigrationPhaseOpen);
        require(_tokens <= balances[msg.sender]);
        transfer(0x0, _tokens);
        tokensIssuedTotal = tokensIssuedTotal.sub(_tokens);
        emit TokenExchangeRequested(msg.sender, _tokens);
    }

    // ERC20 functions -------------------

    /* Transfer out any accidentally sent ERC20 tokens */

    function transferAnyERC20Token(address tokenAddress, uint amount) public onlyOwner returns (bool success) {
        return ERC20Interface(tokenAddress).transfer(owner, amount);
    }

    /* Override "transfer" */

    function transfer(address _to, uint _amount) public returns (bool success) {
        require(tokensTradeable);
        require(_amount <= unlockedTokensInternal(msg.sender));
        return super.transfer(_to, _amount);
    }

    /* Override "transferFrom" */

    function transferFrom(address _from, address _to, uint _amount) public returns (bool success) {
        require(tokensTradeable);
        require(_amount <= unlockedTokensInternal(_from)); 
        return super.transferFrom(_from, _to, _amount);
    }

    /* Multiple token transfers from one address to save gas */

    function transferMultiple(address[] _addresses, uint[] _amounts) external {
        require(tokensTradeable);
        require(_addresses.length <= 100);
        require(_addresses.length == _amounts.length);

        // check token amounts
        uint tokens_to_transfer = 0;
        for (uint i = 0; i < _addresses.length; i++) {
            tokens_to_transfer = tokens_to_transfer.add(_amounts[i]);
        }
        require(tokens_to_transfer <= unlockedTokensInternal(msg.sender));

        // do the transfers
        for (i = 0; i < _addresses.length; i++) {
            super.transfer(_addresses[i], _amounts[i]);
        }
    }

}