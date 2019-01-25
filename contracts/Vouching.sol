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
  uint256 public constant ANSWER_WINDOW = 7 days;
  uint256 public constant APPEAL_WINDOW = 9 days;

  event Vouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Unvouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Registered(uint256 indexed id, address indexed addr, address owner, uint256 minimumStake, string metadataURI, bytes32 metadataHash);
  event Challenged(uint256 indexed id, uint256 indexed challengeID, address indexed challenger, uint256 amount, string metadataURI, bytes32 metadataHash);
  event Accepted(uint256 indexed challengeID);
  event Rejected(uint256 indexed challengeID);
  event Confirmed(uint256 indexed challengeID);
  event Appealed(uint256 indexed challengeID, address indexed appealer, uint256 amount);
  event Sustained(uint256 indexed challengeID, address indexed overseer);
  event Overruled(uint256 indexed challengeID, address indexed overseer);

  enum Answer { PENDING, ACCEPTED, REJECTED }
  enum Resolution { PENDING, SUSTAINED, OVERRULED, CONFIRMED }

  struct Entry {
    uint256 id;
    address addr;
    address owner;
    string metadataURI;
    bytes32 metadataHash;
    uint256 minimumStake;
    uint256 totalVouched;
    uint256 totalAvailable;
    address[] vouchersAddresses;
    mapping (address => Voucher) vouchers;
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
  address private overseer_;
  uint256 private appealFee_;
  uint256 private minimumStake_;
  Entry[] private entries_;
  // TODO: move challenges within entries
  Challenge[] private challenges_;

  modifier existingEntry(uint256 _id) {
    require(_existsEntry(_id), "Could not find a vouched entry with the given ID");
    _;
  }

  modifier existingChallenge(uint256 _id) {
    require(_existsChallenge(_id), "Could not find a challenge with the given ID");
    _;
  }

  modifier onlyOverseer() {
    require(msg.sender == overseer_, "Given method can only be called by the overseer");
    _;
  }

  /**
   * @dev Initializer function. Called only once when a proxy for the contract is created.
   * @param _minimumStake uint256 that defines the minimum initial amount of vouched tokens a dependency can have when being created.
   * @param _token ERC20 token to be used for vouching on dependencies.
   */
  function initialize(ERC20 _token, uint256 _minimumStake, uint256 _appealFee, address _overseer) initializer public {
    require(_token != address(0), "Token address cannot be zero");
    require(_appealFee <= PCT_BASE, "The appeal fee must be lower than 100% (10**18)");

    token_ = _token;
    overseer_ = _overseer;
    appealFee_ = _appealFee;
    minimumStake_ = _minimumStake;
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
   * @dev Tells the address of the overseer.
   * @return The address of the overseer in charge of the vouching contract.
   */
  function overseer() public view returns(address) {
    return overseer_;
  }

  /**
   * @dev Tells the address of an entry
   */
  function addr(uint256 _id) public view returns (address) {
    return _existsEntry(_id) ? entries_[_id].addr : address(0);
  }

  /**
   * @dev Tells the owner of an entry
   */
  function owner(uint256 _id) public view returns (address) {
    return _existsEntry(_id) ? entries_[_id].owner : address(0);
  }

  /**
   * @dev Tells the minimum stake of an entry
   */
  function minStake(uint256 _id) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].minimumStake : uint256(0);
  }

  /**
   * @dev Tells the total vouched amount for an entry
   */
  function totalVouched(uint256 _id) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].totalVouched : uint256(0);
  }

  /**
   * @dev Tells the vouched amount of a voucher for an entry
   */
  function vouched(uint256 _id, address _voucher) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].vouchers[_voucher].vouched : uint256(0);
  }

  /**
   * @dev Tells the vouched amount that is blocked for an entry.
   * This amount is the total vouched amount blocked due to pending challenges.
   */
  function totalBlocked(uint256 _id) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].totalVouched.sub(entries_[_id].totalAvailable) : uint256(0);
  }

  /**
   * @dev Tells the vouched amount that is blocked for a voucher of an entry.
   * This amount is the voucher's vouched amount blocked due to pending challenges.
   */
  function blocked(uint256 _id, address _voucher) public view returns (uint256) {
    return _existsEntry(_id) ? vouched(_id, _voucher).sub(available(_id, _voucher)) : uint256(0);
  }

  /**
   * @dev Tells the vouched amount that is available for an entry. 
   * This amount is the total vouched amount available for unvouching or new challenges.
   */
  function totalAvailable(uint256 _id) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].totalAvailable : uint256(0);
  }

  /**
   * @dev Tells the vouched amount that is available for a voucher of an entry. 
   * This amount is the voucher's vouched amount available for unvouching or new challenges.
   */
  function available(uint256 _id, address _voucher) public view returns (uint256) {
    return _existsEntry(_id) ? entries_[_id].vouchers[_voucher].available : uint256(0);
  }

  /**
   * @dev Tells the challenger of a challenge
   */
  function challenger(uint256 _challengeID) public view returns (address) {
    return _existsChallenge(_challengeID) ? challenges_[_challengeID].challenger : address(0);
  }

  /**
   * @dev Tells the entry being challenged
   */
  function challengeTarget(uint256 _challengeID) public view returns (uint256) {
    return _existsChallenge(_challengeID) ? challenges_[_challengeID].entryID : uint256(0);
  }

  /**
   * @dev Tells the vouched amount for a challenge
   */
  function challengeAmount(uint256 _challengeID) public view returns (uint256) {
    return _existsChallenge(_challengeID) ? challenges_[_challengeID].amount : uint256(0);
  }

  /**
   * @dev Tells the metadata associated with a challenge
   */
  function challengeMetadata(uint256 _challengeID) public view returns (string, bytes32) {
    if (!_existsChallenge(_challengeID)) return ("", bytes32(0));
    Challenge memory _challenge = challenges_[_challengeID];
    return (_challenge.metadataURI, _challenge.metadataHash);
  }

  /**
   * @dev Tells the owner's answer to a challenge
   */
  function challengeAnswer(uint256 _challengeID) public view returns (Answer, uint256) {
    if (!_existsChallenge(_challengeID)) return (Answer.PENDING, uint256(0));
    Challenge memory _challenge = challenges_[_challengeID];
    return (_challenge.answer, _challenge.answeredAt);
  }

  /**
   * @dev Tells the challenge's appeal
   */
  function challengeAppeal(uint256 _challengeID) public view returns (address appealer, uint256 amount, uint256 createdAt) {
    if (!_existsChallenge(_challengeID)) return (address(0), uint256(0), uint256(0));
    Appeal memory _appeal = challenges_[_challengeID].appeal;
    return (_appeal.appealer, _appeal.amount, _appeal.createdAt);
  }

  /**
   * @dev Tells the resolution of a challenge
   */
  function challengeResolution(uint256 _challengeID) public view returns (Resolution) {
    return _existsChallenge(_challengeID) ? challenges_[_challengeID].resolution : Resolution.PENDING;
  }

  /**
   * @dev Generates a fresh ID and adds a new `vouched` entry to the vouching contract, owned by the sender, with `amount`
   * initial ZEP tokens sent by the sender. Requires vouching at least `minStake` tokens, which is a constant value.
   */
  function register(address _addr, uint256 _amount, string _metadataURI, bytes32 _metadataHash) public {
    require(_addr != address(0), "Entry address cannot be a zero address");
    require(_amount >= minimumStake_, "Initial vouched amount must be equal to or greater than the minimum stake");

    uint256 _id = entries_.length++;
    uint256 _vouchedAmount = _amount.sub(minimumStake_);
    Entry storage entry_ = entries_[_id];
    entry_.id = _id;
    entry_.addr = _addr;
    entry_.owner = msg.sender;
    entry_.metadataURI = _metadataURI;
    entry_.metadataHash = _metadataHash;
    entry_.minimumStake = minimumStake_;
    entry_.totalVouched = _vouchedAmount;
    entry_.totalAvailable = _vouchedAmount;
    emit Registered(_id, _addr, msg.sender, minimumStake_, _metadataURI, _metadataHash);

    if (_vouchedAmount > 0) {
      Voucher storage voucher_ = entry_.vouchers[msg.sender];
      if (voucher_.addr == address(0)) {
        voucher_.addr = msg.sender;
        entry_.vouchersAddresses.push(msg.sender);
      }
      voucher_.vouched = _vouchedAmount;
      voucher_.available = _vouchedAmount;
      emit Vouched(_id, msg.sender, _vouchedAmount);
    }

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Increases the vouch for the package identified by `id` by `amount` for `sender`.
   */
  function vouch(uint256 _id, uint256 _amount) public existingEntry(_id) {
    require(_amount > 0, "The amount of tokens to be vouched must be greater than zero");

    Entry storage entry_ = entries_[_id];
    entry_.totalVouched = entry_.totalVouched.add(_amount);
    entry_.totalAvailable = entry_.totalAvailable.add(_amount);

    Voucher storage voucher_ = entry_.vouchers[msg.sender];
    if (voucher_.addr == address(0)) {
      voucher_.addr = msg.sender;
      entry_.vouchersAddresses.push(msg.sender);
    }
    voucher_.vouched = voucher_.vouched.add(_amount);
    voucher_.available = voucher_.available.add(_amount);
    emit Vouched(_id, msg.sender, _amount);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Decreases the vouch for the package identified by `id` by `amount` for `sender`. Note that if `sender` is the
   * `vouched` owner, he cannot decrease his vouching under `minStake`.
   */
  function unvouch(uint256 _id, uint256 _amount) public existingEntry(_id) {
    require(_amount > 0, "The amount of tokens to be unvouched must be greater than zero");
    require(_amount <= available(_id, msg.sender), "The amount of tokens to be unvouched cannot be granter than your unblocked amount");

    Entry storage entry_ = entries_[_id];
    entry_.totalVouched = entry_.totalVouched.sub(_amount);
    entry_.totalAvailable = entry_.totalAvailable.sub(_amount);

    Voucher storage voucher_ = entry_.vouchers[msg.sender];
    voucher_.vouched = voucher_.vouched.sub(_amount);
    voucher_.available = voucher_.available.sub(_amount);
    emit Unvouched(_id, msg.sender, _amount);
    // TODO: remove voucher from entry if possible

    token_.safeTransfer(msg.sender, _amount);
  }

  /**
   * @dev Creates a new challenge with a fresh id in a _pending_ state towards a package for an `amount` of tokens,
   * where the details of the challenge are in the URI specified.
   */
  function challenge(uint256 _id, uint256 _fee, string _metadataURI, bytes32 _metadataHash) public existingEntry(_id) {
    require(_fee <= PCT_BASE, "The challenge fee must be lower than 100% (100e16)");
    require(totalAvailable(_id) > 0, "Given entry does not have an available amount");
    require(msg.sender != owner(_id), "Vouched entries cannot be challenged by their owner");
    // TODO: allowing challengers to tell a percentage here can block all the vouchers tokens, we could use labels instea

    Entry storage entry_ = entries_[_id];
    uint256 _amount = entry_.totalAvailable.mul(_fee).div(PCT_BASE);
    entry_.totalAvailable = entry_.totalAvailable.sub(_amount);

    uint256 _challengeID = challenges_.length++;
    Challenge storage challenge_ = challenges_[_challengeID];
    challenge_.id = _challengeID;
    challenge_.entryID = _id;
    challenge_.amount = _amount;
    challenge_.createdAt = now;
    challenge_.challenger = msg.sender;
    challenge_.metadataURI = _metadataURI;
    challenge_.metadataHash = _metadataHash;
    challenge_.answer = Answer.PENDING;
    challenge_.resolution = Resolution.PENDING;
    emit Challenged(_id, _challengeID, msg.sender, _amount, _metadataURI, _metadataHash);

    for(uint256 i = 0; i < entry_.vouchersAddresses.length; i++) {
      Voucher storage voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
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
    require(msg.sender == owner(challenge_.entryID) || !_withinAnswerPeriod(challenge_), "Challenges can only be answered by the entry owner during the answer period");

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
    require(msg.sender == owner(challenge_.entryID) || !_withinAnswerPeriod(challenge_), "Challenges can only be answered by the entry owner during the answer period");

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
    require(_withinAppealPeriod(challenge_), "The appeal period has ended");
    require(challenge_.answer != Answer.PENDING, "Cannot appeal a not-answered challenge");
    require(challenge_.appeal.appealer == address(0), "Given challenge was already appealed");
    require(msg.sender != owner(challenge_.entryID), "The owner of a vouched entry can not appeal their own decision");

    Appeal storage appeal_ = challenge_.appeal;
    appeal_.appealer = msg.sender;
    appeal_.createdAt = now;
    appeal_.amount = challenge_.amount.mul(appealFee_).div(PCT_BASE);
    emit Appealed(_challengeID, msg.sender, appeal_.amount);

    token_.safeTransferFrom(msg.sender, this, appeal_.amount);
  }

  /**
   * @dev Accepts an appeal on a challenge. Can only be called by the overseer.
   */
  function sustain(uint256 _challengeID) public onlyOverseer existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    Appeal storage appeal_ = challenge_.appeal;
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(appeal_.appealer != address(0), "Cannot sustain a not-appealed challenge");

    challenge_.resolution = Resolution.SUSTAINED;
    emit Sustained(_challengeID, overseer_);

    uint256 i;
    uint256 _blocked;
    Voucher storage voucher_;
    Entry storage entry_ = entries_[challenge_.entryID];

    if (challenge_.answer == Answer.REJECTED) {
      entry_.totalVouched = entry_.totalVouched.sub(challenge_.amount);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) voucher_.vouched = voucher_.vouched.sub(_blocked);
        // no need to reset the voucher's blocked amount for the challenge
      }

      token_.safeTransfer(appeal_.appealer, appeal_.amount.mul(2));
      token_.safeTransfer(challenge_.challenger, challenge_.amount.mul(2).sub(appeal_.amount));
    }
    else {
      uint256 profit = challenge_.amount.sub(appeal_.amount);
      entry_.totalVouched = entry_.totalVouched.add(profit);
      entry_.totalAvailable = entry_.totalAvailable.add(challenge_.amount).add(profit);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) {
          uint256 appealPropCost = appeal_.amount.mul(_blocked).div(challenge_.amount);
          uint256 voucherProfit = _blocked.sub(appealPropCost);
          voucher_.vouched = voucher_.vouched.add(voucherProfit);
          voucher_.available = voucher_.available.add(_blocked).add(voucherProfit);
          // no need to reset the voucher's blocked amount for the challenge
        }
      }

      token_.safeTransfer(appeal_.appealer, appeal_.amount.mul(2));
    }
  }

  /**
   * @dev Rejects an appeal on a challenge. Can only be called by the overseer.
   */
  function overrule(uint256 _challengeID) public onlyOverseer existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    Appeal storage appeal_ = challenge_.appeal;
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(appeal_.appealer != address(0), "Cannot overrule a not-appealed challenge");

    challenge_.resolution = Resolution.OVERRULED;
    emit Overruled(_challengeID, overseer_);

    uint256 i;
    uint256 profit;
    uint256 _blocked;
    uint256 voucherProfit;
    Voucher storage voucher_;
    Entry storage entry_ = entries_[challenge_.entryID];

    if (challenge_.answer == Answer.ACCEPTED) {
      profit = appeal_.amount;
      entry_.totalVouched = entry_.totalVouched.sub(challenge_.amount).add(profit);
      entry_.totalAvailable = entry_.totalAvailable.add(profit);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) {
          voucherProfit = appeal_.amount.mul(_blocked).div(challenge_.amount);
          voucher_.vouched = voucher_.vouched.sub(_blocked).add(voucherProfit);
          voucher_.available = voucher_.available.add(voucherProfit);
          // no need to reset the voucher's blocked amount for the challenge
        }
      }

      token_.safeTransfer(challenge_.challenger, challenge_.amount.mul(2));
    }
    else {
      profit = challenge_.amount.add(appeal_.amount);
      entry_.totalVouched = entry_.totalVouched.add(profit);
      entry_.totalAvailable = entry_.totalAvailable.add(challenge_.amount).add(profit);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) {
          uint256 appealPropProfit = appeal_.amount.mul(_blocked).div(challenge_.amount);
          voucherProfit = _blocked.add(appealPropProfit);
          voucher_.vouched = voucher_.vouched.add(voucherProfit);
          voucher_.available = voucher_.available.add(_blocked).add(voucherProfit);
          // no need to reset the voucher's blocked amount for the challenge
        }
      }
    }
  }

  /**
   * @dev Confirms the result of a challenge if it has not been appealed and the challenge period has passed.
   * Transfers tokens associated to the challenge as needed.
   */
  function confirm(uint256 _challengeID) public existingChallenge(_challengeID) {
    Challenge storage challenge_ = challenges_[_challengeID];
    require(challenge_.answer != Answer.PENDING, "Cannot confirm a non-answered challenge");
    require(challenge_.resolution == Resolution.PENDING, "Given challenge was already resolved");
    require(challenge_.appeal.appealer == address(0), "Cannot confirm an appealed challenge");
    require(!_withinAppealPeriod(challenge_), "Cannot confirm a challenge during the appeal period");

    challenge_.resolution = Resolution.CONFIRMED;
    emit Confirmed(_challengeID);

    uint256 i;
    uint256 _blocked;
    Voucher storage voucher_;
    Entry storage entry_ = entries_[challenge_.entryID];

    if (challenge_.answer == Answer.ACCEPTED) {
      entry_.totalVouched = entry_.totalVouched.sub(challenge_.amount);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) voucher_.vouched = voucher_.vouched.sub(_blocked);
        // no need to reset the voucher's blocked amount for the challenge
      }

      token_.safeTransfer(challenge_.challenger, challenge_.amount.mul(2));
    }
    else {
      uint256 profit = challenge_.amount;
      entry_.totalVouched = entry_.totalVouched.add(challenge_.amount);
      entry_.totalAvailable = entry_.totalAvailable.add(challenge_.amount).add(profit);

      for(i = 0; i < entry_.vouchersAddresses.length; i++) {
        voucher_ = entry_.vouchers[entry_.vouchersAddresses[i]];
        _blocked = voucher_.blockedPerChallenge[_challengeID];
        if (_blocked > uint256(0)) {
          voucher_.vouched = voucher_.vouched.add(_blocked);
          voucher_.available = voucher_.available.add(_blocked).add(_blocked);
          // no need to reset the voucher's blocked amount for the challenge
        }
      }
    }
  }

  function _withinAnswerPeriod(Challenge storage challenge_) internal view returns (bool) {
    return challenge_.createdAt + ANSWER_WINDOW >= now;
  }

  function _withinAppealPeriod(Challenge storage challenge_) internal view returns (bool) {
    return challenge_.answeredAt + APPEAL_WINDOW >= now;
  }

  function _existsEntry(uint256 _id) internal view returns (bool) {
    return _id < entries_.length;
  }

  function _existsChallenge(uint256 _id) internal view returns (bool) {
    return _id < challenges_.length;
  }
}
