pragma solidity ^0.4.24;

import "zos-lib/contracts/Initializable.sol";
import "openzeppelin-eth/contracts/math/SafeMath.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-eth/contracts/token/ERC20/SafeERC20.sol";

/**
 * @title Vouching
 * @dev Contract for staking tokens to back entries.
 */
contract Vouching is Initializable {
  using SafeMath for uint256;
  using SafeERC20 for ERC20;

  uint256 public constant PCT_BASE = 10 ** 18; // 100e16 = 100%;
  uint256 public constant MAX_CHALLENGE_FEE = 50 * 10 ** 16; // 50e16 = 50%;
  uint256 public constant MAX_VOUCHERS = 230;
  uint256 public constant ANSWER_WINDOW = 7 days;
  uint256 public constant APPEAL_WINDOW = 9 days;

  event OwnershipTransferred(uint256 indexed id, address indexed oldOwner, address indexed newOwner);
  event AppealsResolutionTransferred(address indexed oldAppealsResolver, address indexed newAppealsResolver);
  event Vouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Unvouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Registered(uint256 indexed id, address indexed addr, address owner, uint256 minimumStake, string metadataURI, bytes32 metadataHash);
  event Challenged(uint256 indexed id, uint256 indexed challengeID, address indexed challenger, uint256 amount, string metadataURI, bytes32 metadataHash);
  event Accepted(uint256 indexed challengeID);
  event Rejected(uint256 indexed challengeID);
  event Confirmed(uint256 indexed challengeID);
  event Appealed(uint256 indexed challengeID, address indexed appealer, uint256 amount);
  event AppealAffirmed(uint256 indexed challengeID, address indexed appealsResolver);
  event AppealDismissed(uint256 indexed challengeID, address indexed appealsResolver);

  enum Answer { PENDING, ACCEPTED, REJECTED }
  enum Resolution { PENDING, APPEAL_AFFIRMED, APPEAL_DISMISSED, CONFIRMED }

  struct Entry {
    uint256 id;
    address addr;
    address owner;
    string metadataURI;
    bytes32 metadataHash;
    uint256 minimumStake;
    uint256 totalVouched;
    uint256 totalAvailable;
    address[] vouchersAddress;
    mapping (address => Voucher) vouchers;
    mapping (address => uint256) vouchersAddressIndex;
  }

  struct Voucher {
    address addr;
    uint256 vouched;
    uint256 available;
    mapping (uint256 => uint256) blockedPerChallenge;
  }

  struct Challenge {
    uint256 id;
    uint256 entryID;
    address challenger;
    uint256 amount;
    uint256 createdAt;
    string metadataURI;
    bytes32 metadataHash;
    uint256 answeredAt;
    Answer answer;
    Appeal appeal;
    Resolution resolution;
  }

  struct Appeal {
    address appealer;
    uint256 amount;
    uint256 createdAt;
  }

  ERC20 private token_;
  uint256 private appealFee_;
  uint256 private minimumStake_;
  address private appealsResolver_;
  Entry[] private entries_;
  Challenge[] private challenges_;

  modifier existingEntry(uint256 _entryID) {
    require(_existsEntry(_entryID), "Could not find a vouched entry with the given ID");
    _;
  }

  modifier existingChallenge(uint256 _challengeID) {
    require(_existsChallenge(_challengeID), "Could not find a challenge with the given ID");
    _;
  }

  modifier onlyAppealsResolver() {
    require(msg.sender == appealsResolver_, "Given method can only be called by the appealsResolver");
    _;
  }

  /**
   * @dev Initializer function. Called only once when a proxy for the contract is created.
   * @param _minimumStake uint256 that defines the minimum initial amount of vouched tokens a dependency can have when being created.
   * @param _token ERC20 token to be used for vouching on dependencies.
   */
  function initialize(ERC20 _token, uint256 _minimumStake, uint256 _appealFee, address _appealsResolver) initializer public {
    require(_token != address(0), "The token address cannot be zero");
    require(_appealsResolver != address(0), "The appeals resolver address cannot be zero");

    token_ = _token;
    appealFee_ = _appealFee;
    minimumStake_ = _minimumStake;
    appealsResolver_ = _appealsResolver;
  }

  /**
   * @dev Tells the the initial minimum amount of vouched tokens a dependency can have when being created.
   * @return A uint256 number with the minimumStake value.
   */
  function minimumStake() public view returns(uint256) {
    return minimumStake_;
  }

  /**
   * @dev Tells the ERC20 token being used for vouching.
   * @return The address of the ERC20 token being used for vouching.
   */
  function token() public view returns(ERC20) {
    return token_;
  }

  /**
   * @dev Tells the appeal payout fee.
   * @return The appeal payout fee.
   */
  function appealFee() public view returns(uint256) {
    return appealFee_;
  }

  /**
   * @dev Tells the address of the appeals resolver.
   * @return The address of the appeals resolver in charge of the vouching contract.
   */
  function appealsResolver() public view returns(address) {
    return appealsResolver_;
  }

  /**
   * @dev Tells the information associated to an entry
   */
  function getEntry(uint256 _entryID)
    public view returns (
      address addr,
      address owner,
      string metadataURI,
      bytes32 metadataHash,
      uint256 minimumStake,
      uint256 totalVouched,
      uint256 totalAvailable,
      uint256 totalBlocked
    )
  {
    if (!_existsEntry(_entryID)) return (address(0), address(0), "", bytes32(0), uint256(0), uint256(0), uint256(0), uint256(0));
    Entry storage e = entries_[_entryID];
    uint256 _totalBlocked = e.totalVouched.sub(e.totalAvailable);
    return (e.addr, e.owner, e.metadataURI, e.metadataHash, e.minimumStake, e.totalVouched, e.totalAvailable, _totalBlocked);
  }

  /**
   * @dev Tells the information associated to a challenge
   */
  function getChallenge(uint256 _challengeID)
    public view returns (
      uint256 entryID,
      address challenger,
      uint256 amount,
      uint256 createdAt,
      string metadataURI,
      bytes32 metadataHash,
      Answer answer,
      uint256 answeredAt,
      Resolution resolution
    )
  {
    if (!_existsChallenge(_challengeID)) return (uint256(0), address(0), uint256(0), uint256(0), "", bytes32(0), Answer.PENDING, uint256(0), Resolution.PENDING);
    Challenge storage c = challenges_[_challengeID];
    return (c.entryID, c.challenger, c.amount, c.createdAt, c.metadataURI, c.metadataHash, c.answer, c.answeredAt, c.resolution);
  }

  /**
   * @dev Tells the information associated to a challenge's appeal
   */
  function getAppeal(uint256 _challengeID) public view returns (address appealer, uint256 amount, uint256 createdAt) {
    if (!_existsChallenge(_challengeID)) return (address(0), uint256(0), uint256(0));
    Appeal storage a = challenges_[_challengeID].appeal;
    return (a.appealer, a.amount, a.createdAt);
  }

  /**
   * @dev Tells the vouched, available and blocked amounts of a voucher for an entry
   */
  function getVouched(uint256 _entryID, address _voucher) public view returns (uint256 vouched, uint256 available, uint256 blocked) {
    if (!_existsEntry(_entryID)) return (uint256(0), uint256(0), uint256(0));
    uint256 _vouchedAmount = _vouched(_entryID, _voucher);
    uint256 _availableAmount = _available(_entryID, _voucher);
    return (_vouchedAmount, _availableAmount, _vouchedAmount.sub(_availableAmount));
  }

  /**
   * @dev Transfers the ownership of a given entry
   */
  function transferOwnership(uint256 _entryID, address _newOwner) public existingEntry(_entryID) {
    require(_newOwner != address(0), "New owner address cannot be zero");
    require(_isOwner(msg.sender, _entryID), "Transfer ownership can only be called by the owner of the entry");
    entries_[_entryID].owner = _newOwner;
    emit OwnershipTransferred(_entryID, msg.sender, _newOwner);
  }

  /**
   * @dev Transfers the appeals resolution to another address
   */
  function transferAppealsResolution(address _newAppealsResolver) public onlyAppealsResolver {
    require(_newAppealsResolver != address(0), "New appeals resolver address cannot be zero");
    appealsResolver_ = _newAppealsResolver;
    emit AppealsResolutionTransferred(msg.sender, _newAppealsResolver);
  }

  /**
   * @dev Generates a fresh ID and adds a new `vouched` entry to the vouching contract, owned by the sender, with `amount`
   * initial ZEP tokens sent by the sender. Requires vouching at least `minStake` tokens, which is a constant value.
   */
  function register(address _addr, uint256 _amount, string _metadataURI, bytes32 _metadataHash) public {
    require(_addr != address(0), "Entry address cannot be zero");
    require(_amount >= minimumStake_, "Initial vouched amount must be equal to or greater than the minimum stake");

    uint256 _entryID = entries_.length++;
    uint256 _vouchedAmount = _amount.sub(minimumStake_);
    Entry storage entry_ = entries_[_entryID];
    entry_.id = _entryID;
    entry_.addr = _addr;
    entry_.owner = msg.sender;
    entry_.metadataURI = _metadataURI;
    entry_.metadataHash = _metadataHash;
    entry_.minimumStake = minimumStake_;
    entry_.totalVouched = _vouchedAmount;
    entry_.totalAvailable = _vouchedAmount;
    emit Registered(_entryID, _addr, msg.sender, minimumStake_, _metadataURI, _metadataHash);
    if (_vouchedAmount > 0) _vouch(entry_, msg.sender, _vouchedAmount);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Increases the vouch for the package identified by `id` by `amount` for `sender`.
   */
  function vouch(uint256 _entryID, uint256 _amount) public existingEntry(_entryID) {
    require(_amount > 0, "The amount of tokens to be vouched must be greater than zero");

    Entry storage entry_ = entries_[_entryID];
    entry_.totalVouched = entry_.totalVouched.add(_amount);
    entry_.totalAvailable = entry_.totalAvailable.add(_amount);
    _vouch(entry_, msg.sender, _amount);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Decreases the vouch for the package identified by `id` by `amount` for `sender`. Note that if `sender` is the
   * `vouched` owner, he cannot decrease his vouching under `minStake`.
   */
  function unvouch(uint256 _entryID, uint256 _amount) public existingEntry(_entryID) {
    require(_amount > 0, "The amount of tokens to be unvouched must be greater than zero");
    require(_amount <= _available(_entryID, msg.sender), "The amount of tokens to be unvouched cannot be granter than your unblocked amount");

    Entry storage entry_ = entries_[_entryID];
    entry_.totalVouched = entry_.totalVouched.sub(_amount);
    entry_.totalAvailable = entry_.totalAvailable.sub(_amount);

    Voucher storage voucher_ = entry_.vouchers[msg.sender];
    voucher_.vouched = voucher_.vouched.sub(_amount);
    voucher_.available = voucher_.available.sub(_amount);
    if (voucher_.vouched == 0) _removeVoucher(entry_, msg.sender);
    emit Unvouched(_entryID, msg.sender, _amount);

    token_.safeTransfer(msg.sender, _amount);
  }

  /**
   * @dev Creates a new challenge with a fresh id in a _pending_ state towards a package for an `amount` of tokens,
   * where the details of the challenge are in the URI specified.
   */
  function challenge(uint256 _entryID, uint256 _fee, string _metadataURI, bytes32 _metadataHash) public existingEntry(_entryID) {
    Entry storage entry_ = entries_[_entryID];
    require(entry_.totalAvailable > 0, "Given entry does not have an available amount");
    require(_fee <= MAX_CHALLENGE_FEE, "The challenge fee must be lower than or equal to 50% (50e16)");
    require(!_isOwner(msg.sender, _entryID), "Vouched entries cannot be challenged by their owner");

    uint256 _amount = entry_.totalAvailable.mul(_fee).div(PCT_BASE);
    entry_.totalAvailable = entry_.totalAvailable.sub(_amount);

    uint256 _challengeID = challenges_.length++;
    Challenge storage challenge_ = challenges_[_challengeID];
    challenge_.id = _challengeID;
    challenge_.entryID = _entryID;
    challenge_.amount = _amount;
    challenge_.createdAt = now;
    challenge_.challenger = msg.sender;
    challenge_.metadataURI = _metadataURI;
    challenge_.metadataHash = _metadataHash;
    challenge_.answer = Answer.PENDING;
    challenge_.resolution = Resolution.PENDING;
    emit Challenged(_entryID, _challengeID, msg.sender, _amount, _metadataURI, _metadataHash);

    for(uint256 i = 0; i < entry_.vouchersAddress.length; i++) {
      Voucher storage voucher_ = entry_.vouchers[entry_.vouchersAddress[i]];
      if (voucher_.available > uint256(0)) {
        uint256 _blocked = voucher_.available.mul(_fee).div(PCT_BASE);
        voucher_.available = voucher_.available.sub(_blocked);
        voucher_.blockedPerChallenge[_challengeID] = _blocked;
      }
    }

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Accepts a challenge. Can only be called by the owner of the challenged entry.
   */
  function accept(uint256 _challengeID) public existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.answer == Answer.PENDING, "Given challenge was already answered");
    require(_canAnswer(msg.sender, challenge_), "Challenges can only be answered by the entry owner during the answer period");

    challenge_.answer = Answer.ACCEPTED;
    challenge_.answeredAt = now;
    emit Accepted(_challengeID);
  }

  /**
   * @dev Rejects a challenge. Can only be called by the owner of the challenged entry.
   */
  function reject(uint256 _challengeID) public existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.answer == Answer.PENDING, "Given challenge was already answered");
    require(_canAnswer(msg.sender, challenge_), "Challenges can only be answered by the entry owner during the answer period");

    challenge_.answer = Answer.REJECTED;
    challenge_.answeredAt = now;
    emit Rejected(_challengeID);
  }

  /**
   * @dev Appeals a decision by the vouched entry owner to accept or reject a decision. Any ZEP token holder can
   * perform an appeal, staking a certain amount of tokens on it.
   */
  function appeal(uint256 _challengeID) public existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    Appeal storage appeal_ = challenge_.appeal;
    require(_withinAppealPeriod(challenge_), "The appeal period has ended");
    require(appeal_.appealer == address(0), "Given challenge was already appealed");
    require(challenge_.answer != Answer.PENDING, "Cannot appeal a not-answered challenge");
    require(!_isOwner(msg.sender, challenge_.entryID), "The owner of a vouched entry can not appeal their own decision");

    appeal_.appealer = msg.sender;
    appeal_.createdAt = now;
    appeal_.amount = challenge_.amount.mul(appealFee_).div(PCT_BASE);
    emit Appealed(_challengeID, msg.sender, appeal_.amount);

    token_.safeTransferFrom(msg.sender, this, appeal_.amount);
  }

  /**
   * @dev Affirms an appeal on a challenge. Can only be called by the appeals resolver.
   */
  function affirmAppeal(uint256 _challengeID) public onlyAppealsResolver existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(challenge_.appeal.appealer != address(0), "Cannot affirm a not-appealed challenge");

    challenge_.resolution = Resolution.APPEAL_AFFIRMED;
    emit AppealAffirmed(_challengeID, appealsResolver_);

    if (challenge_.answer == Answer.ACCEPTED) _releaseBlockedAmounts(challenge_);
    else _suppressBlockedAmountsAndPayChallenger(challenge_);
    token_.safeTransfer(challenge_.appeal.appealer, challenge_.appeal.amount);
  }

  /**
   * @dev Rejects an appeal on a challenge. Can only be called by the appeals resolver.
   */
  function dismissAppeal(uint256 _challengeID) public onlyAppealsResolver existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(challenge_.appeal.appealer != address(0), "Cannot dismiss a not-appealed challenge");

    challenge_.resolution = Resolution.APPEAL_DISMISSED;
    emit AppealDismissed(_challengeID, appealsResolver_);

    if (challenge_.answer == Answer.REJECTED) _releaseBlockedAmountsIncludingAppeal(challenge_);
    else _suppressBlockedAmountsAndPayChallengerIncludingAppeal(challenge_);
  }

  /**
   * @dev Confirms the result of a challenge if it has not been appealed and the challenge period has passed.
   * Transfers tokens associated to the challenge as needed.
   */
  function confirm(uint256 _challengeID) public existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.answer != Answer.PENDING, "Cannot confirm a not-answered challenge");
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(challenge_.appeal.appealer == address(0), "Cannot confirm an appealed challenge");
    require(!_withinAppealPeriod(challenge_), "Cannot confirm a challenge during the appeal period");

    challenge_.resolution = Resolution.CONFIRMED;
    emit Confirmed(_challengeID);

    if (challenge_.answer == Answer.REJECTED) _releaseBlockedAmounts(challenge_);
    else _suppressBlockedAmountsAndPayChallenger(challenge_);
  }

  function _existsEntry(uint256 _entryID) internal view returns (bool) {
    return _entryID < entries_.length;
  }

  function _existsChallenge(uint256 _entryID) internal view returns (bool) {
    return _entryID < challenges_.length;
  }

  function _isOwner(address _someone, uint256 _entryID) internal view returns (bool) {
    return entries_[_entryID].owner == _someone;
  }

  function _vouched(uint256 _entryID, address _voucher) internal view returns (uint256) {
    return entries_[_entryID].vouchers[_voucher].vouched;
  }

  function _available(uint256 _id, address _voucher) internal view returns (uint256) {
    return entries_[_id].vouchers[_voucher].available;
  }

  function _canAnswer(address _someone, Challenge storage challenge_) internal view returns (bool) {
    return _isOwner(_someone, challenge_.entryID) || !_withinAnswerPeriod(challenge_);
  }

  function _withinAnswerPeriod(Challenge storage challenge_) internal view returns (bool) {
    return challenge_.createdAt.add(ANSWER_WINDOW) >= now;
  }

  function _withinAppealPeriod(Challenge storage challenge_) internal view returns (bool) {
    return challenge_.answeredAt.add(APPEAL_WINDOW) >= now;
  }

  function _vouch(Entry storage entry_, address _voucher, uint256 _amount) internal {
    require(entry_.vouchersAddress.length < MAX_VOUCHERS, "Given entry has reached the maximum amount of vouchers");
    Voucher storage voucher_ = entry_.vouchers[_voucher];
    if (voucher_.addr == address(0)) {
      voucher_.addr = _voucher;
      uint256 _voucherIndex = entry_.vouchersAddress.length;
      entry_.vouchersAddress.push(_voucher);
      entry_.vouchersAddressIndex[_voucher] = _voucherIndex;
    }
    voucher_.vouched = voucher_.vouched.add(_amount);
    voucher_.available = voucher_.available.add(_amount);
    emit Vouched(entry_.id, _voucher, _amount);
  }

  function _suppressBlockedAmountsAndPayChallenger(Challenge storage challenge_) internal {
    _suppressBlockedAmounts(challenge_);
    uint256 _payout = challenge_.amount.mul(2);
    token_.safeTransfer(challenge_.challenger, _payout);
  }

  function _suppressBlockedAmountsAndPayChallengerIncludingAppeal(Challenge storage challenge_) internal {
    _suppressBlockedAmounts(challenge_);
    uint256 _payout = challenge_.amount.mul(2).add(challenge_.appeal.amount);
    token_.safeTransfer(challenge_.challenger, _payout);
  }

  function _suppressBlockedAmounts(Challenge storage challenge_) internal {
    Entry storage entry_ = entries_[challenge_.entryID];
    entry_.totalVouched = entry_.totalVouched.sub(challenge_.amount);

    for(uint256 i = 0; i < entry_.vouchersAddress.length; i++) {
      Voucher storage voucher_ = entry_.vouchers[entry_.vouchersAddress[i]];
      uint256 _blocked = voucher_.blockedPerChallenge[challenge_.id];
      if (_blocked > uint256(0)) {
        voucher_.vouched = voucher_.vouched.sub(_blocked);
        voucher_.blockedPerChallenge[challenge_.id] = uint256(0);
      }
    }
  }

  function _releaseBlockedAmounts(Challenge storage challenge_) internal {
    Entry storage entry_ = entries_[challenge_.entryID];
    entry_.totalVouched = entry_.totalVouched.add(challenge_.amount);
    entry_.totalAvailable = entry_.totalAvailable.add(challenge_.amount.mul(2));

    for(uint256 i = 0; i < entry_.vouchersAddress.length; i++) {
      Voucher storage voucher_ = entry_.vouchers[entry_.vouchersAddress[i]];
      uint256 _blocked = voucher_.blockedPerChallenge[challenge_.id];
      if (_blocked > uint256(0)) {
        voucher_.vouched = voucher_.vouched.add(_blocked);
        voucher_.available = voucher_.available.add(_blocked.mul(2));
        voucher_.blockedPerChallenge[challenge_.id] = uint256(0);
      }
    }
  }

  function _releaseBlockedAmountsIncludingAppeal(Challenge storage challenge_) internal {
    Entry storage entry_ = entries_[challenge_.entryID];
    uint256 _appealAmount = challenge_.appeal.amount;
    uint256 _totalProfit = challenge_.amount.add(_appealAmount);
    entry_.totalVouched = entry_.totalVouched.add(_totalProfit);
    entry_.totalAvailable = entry_.totalAvailable.add(_totalProfit).add(challenge_.amount);

    for(uint256 i = 0; i < entry_.vouchersAddress.length; i++) {
      Voucher storage voucher_ = entry_.vouchers[entry_.vouchersAddress[i]];
      uint256 _blocked = voucher_.blockedPerChallenge[challenge_.id];
      if (_blocked > uint256(0)) {
        uint256 _appealProfit = _appealAmount.mul(_blocked).div(challenge_.amount);
        uint256 _voucherProfit = _blocked.add(_appealProfit);
        voucher_.vouched = voucher_.vouched.add(_voucherProfit);
        voucher_.available = voucher_.available.add(_voucherProfit).add(_blocked);
        voucher_.blockedPerChallenge[challenge_.id] = uint256(0);
      }
    }
  }

  function _removeVoucher(Entry storage entry_, address _voucher) private {
    uint256 _voucherIndex = entry_.vouchersAddressIndex[_voucher];
    uint256 _lastVoucherIndex = entry_.vouchersAddress.length.sub(1);
    address _lastVoucher = entry_.vouchersAddress[_lastVoucherIndex];

    entry_.vouchersAddress[_voucherIndex] = _lastVoucher;
    entry_.vouchersAddress.length--;
    entry_.vouchersAddressIndex[_voucher] = 0;
    entry_.vouchersAddressIndex[_lastVoucher] = _voucherIndex;
  }
}
