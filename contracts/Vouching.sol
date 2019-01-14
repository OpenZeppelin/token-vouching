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

  event Vouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Unvouched(uint256 indexed id, address indexed sender, uint256 amount);
  event Registered(uint256 indexed id, address indexed vouched, address owner, uint256 amount, string metadataURI, bytes32 metadataHash);
  event Challenged(uint256 indexed id, uint256 indexed _challengeID, address indexed challenger, uint256 amount, string challengeURI, bytes32 challengeHash);

  struct Entry {
    uint256 id;
    address vouched;
    address owner;
    uint256 totalAmount;
    string metadataURI;
    bytes32 metadataHash;
  }

  struct Challenge {
    uint256 id;
    uint256 entryId;
    address challenger;
    uint256 amount;
    string metadataURI;
    bytes32 metadataHash;
    // TODO: store state
  }

  ERC20 private token_;
  Entry[] private entries_;
  Challenge[] private challenges_;
  uint256 private minimumStake_;

  // entry id => voucher => amount
  mapping (uint256 => mapping (address => uint256)) private vouchedAmounts_;

  // entry id => challenger => amount
  mapping (uint256 => mapping (address => uint256)) private challengedAmounts_;

  /**
   * @dev Initializer function. Called only once when a proxy for the contract is created.
   * @param _minimumStake uint256 that defines the minimum initial amount of vouched tokens a dependency can have when being created.
   * @param _token ERC20 token to be used for vouching on dependencies.
   */
  function initialize(uint256 _minimumStake, ERC20 _token) initializer public {
    require(_token != address(0), "Token address cannot be zero");
    token_ = _token;
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
   * @dev Tells the address of an entry
   */
  function vouched(uint256 _id) public view returns (address) {
    return exists(_id) ? entries_[_id].vouched : address(0);
  }

  /**
   * @dev Tells the owner of an entry
   */
  function owner(uint256 _id) public view returns (address) {
    return exists(_id) ? entries_[_id].owner : address(0);
  }

  /**
   * @dev Tells the total amount vouched for an entry
   */
  function totalVouched(uint256 _id) public view returns (uint256) {
    return exists(_id) ? entries_[_id].totalAmount : uint256(0);
  }

  /**
   * @dev Tells the amount vouched for entry by a given voucher
   */
  function vouchedAmount(uint256 _id, address _voucher) public view returns (uint256) {
    return exists(_id) ? vouchedAmounts_[_id][_voucher] : uint256(0);
  }

  /**
   * @dev Tells the challenger of a challenge
   */
  function challenger(uint256 _challengeID) public view returns (address) {
    return existsChallenge(_challengeID) ? challenges_[_challengeID].challenger : address(0);
  }

  /**
   * @dev Tells the entry being challenged
   */
  function challengeTarget(uint256 _challengeID) public view returns (uint256) {
    return existsChallenge(_challengeID) ? challenges_[_challengeID].entryId : uint256(0);
  }

  /**
   * @dev Tells the amount vouched for a challenge
   */
  function challengeStake(uint256 _challengeID) public view returns (uint256) {
    return existsChallenge(_challengeID) ? challenges_[_challengeID].amount : uint256(0);
  }

  /**
   * @dev Tells the metadata associated with a challenge
   */
  function challengeMetadata(uint256 _challengeID) public view returns (string, bytes32) {
    if (existsChallenge(_challengeID)) {
      Challenge memory _challenge = challenges_[_challengeID];
      return (_challenge.metadataURI, _challenge.metadataHash);
    }
    return ("", bytes32(0));
  }

  /**
   * @dev Tells the state of a challenge
   */
  function challengeState(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Generates a fresh ID and adds a new `vouched` item to the vouching contract, owned by the sender, with `amount`
   * initial ZEP tokens sent by the sender. Requires vouching at least `minStake` tokens, which is a constant value.
   */
  function register(address _vouched, uint256 _amount, string _metadataURI, bytes32 _metadataHash) public {
    require(_vouched != address(0), "Dependency address cannot be zero");
    require(_amount >= minimumStake_, "Initial vouched amount must be equal to or greater than the minimum stake");

    uint256 _id = entries_.length;
    Entry memory _entry = Entry(_id, _vouched, msg.sender, _amount, _metadataURI, _metadataHash);
    entries_.push(_entry);
    vouchedAmounts_[_id][msg.sender] = _amount;
    emit Registered(_id, _vouched, msg.sender, _amount, _metadataURI, _metadataHash);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Increases the vouch for the package identified by `id` by `amount` for `sender`.
   */
  function vouch(uint256 _id, uint256 _amount) public {
    require(exists(_id), "Could not find an entry to vouch for with the given ID");
    require(_amount > 0, "The amount of tokens to be vouched must be greater than zero");

    entries_[_id].totalAmount = entries_[_id].totalAmount.add(_amount);
    vouchedAmounts_[_id][msg.sender] = vouchedAmounts_[_id][msg.sender].add(_amount);
    emit Vouched(_id, msg.sender, _amount);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Decreases the vouch for the package identified by `id` by `amount` for `sender`. Note that if `sender` is the
   * `vouched` owner, he cannot decrease his vouching under `minStake`.
   */
  function unvouch(uint256 _id, uint256 _amount) public {
    require(exists(_id), "Could not find an entry to unvouch for with the given ID");
    require(_amount > 0, "The amount of tokens to be unvouched must be greater than zero");
    require(_amount <= vouchedAmount(_id, msg.sender), "The amount of tokens to be unvouched cannot be granter than your vouched amount");
    require(owner(_id) != msg.sender || vouchedAmount(_id, msg.sender).sub(_amount) >= minimumStake_, "The vouched amount of tokens cannot be lower than the minimum stake");

    entries_[_id].totalAmount = entries_[_id].totalAmount.sub(_amount);
    vouchedAmounts_[_id][msg.sender] = vouchedAmounts_[_id][msg.sender].sub(_amount);
    emit Unvouched(_id, msg.sender, _amount);

    token_.safeTransfer(msg.sender, _amount);
  }

  /**
   * @dev Creates a new challenge with a fresh id in a _pending_ state towards a package for an `amount` of tokens,
   * where the details of the challenge are in the URI specified.
   */
  function challenge(uint256 _id, uint256 _amount, string _metadataURI, bytes32 _metadataHash) public {
    require(exists(_id), "Could not find an entry to challenge with the given ID");
    require(msg.sender != owner(_id), "Entries owners can not challenge themselves");
    // TODO: validate challenge period holds for the given entry

    uint256 _challengeID = challenges_.length;
    Challenge memory _challenge = Challenge(_challengeID, _id, msg.sender, _amount, _metadataURI, _metadataHash);
    challenges_.push(_challenge);
    challengedAmounts_[_id][msg.sender] = _amount;
    emit Challenged(_id, _challengeID, msg.sender, _amount, _metadataURI, _metadataHash);

    token_.safeTransferFrom(msg.sender, this, _amount);
  }

  /**
   * @dev Accepts a challenge. Can only be called by the owner of the challenged item.
   */
  function accept(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Rejects a challenge. Can only be called by the owner of the challenged item.
   */
  function reject(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Appeals a decision by the vouched item owner to accept or reject a decision. Any ZEP token holder can perform
   * an appeal, staking a certain amount of tokens on it. Note that `amount` may be fixed and depend on the challenge
   * stake, in that case, the second parameter can be removed.
   */
  function appeal(uint256 _challengeID, uint256 _amount) public {
    // TODO: implement
  }

  /**
   * @dev Accepts an appeal on a challenge. Can only be called by an overseer address set in the contract, which will
   * be eventually replaced by a voting system.
   */
  function sustain(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Rejects an appeal on a challenge. Can only be called by an overseer address set in the contract, which will
   * be eventually replaced by a voting system.
   */
  function overrule(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Confirms the result of a challenge if it has not been challenged and the challenge period has passed.
   * Transfers tokens associated to the challenge as needed.
   */
  function confirm(uint256 _challengeID) public {
    // TODO: implement
  }

  /**
   * @dev Tells whether an entry is registered or not
   */
  function exists(uint256 _id) internal returns (bool) {
    return _id < entries_.length;
  }

  /**
   * @dev Tells whether a challenge exists or not
   */
  function existsChallenge(uint256 _challengeID) internal view returns (bool) {
    return _challengeID < challenges_.length;
  }
}
