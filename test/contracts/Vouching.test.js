require('../setup')

import { Contracts, encodeCall, assertEvent, assertRevert } from 'zos-lib'

const BigNumber = web3.BigNumber;
const ZEPToken = artifacts.require('ZEPToken');
const Vouching = artifacts.require('Vouching');
const DependencyMock = artifacts.require('DependencyMock');
const BasicJurisdiction = Contracts.getFromNodeModules('tpl-contracts-eth', 'BasicJurisdiction')
const OrganizationsValidator = Contracts.getFromNodeModules('tpl-contracts-eth', 'OrganizationsValidator')

contract('Vouching', function ([_, tokenOwner, vouchingOwner, developer, transferee, nonContractAddress, jurisdictionOwner, validatorOwner, organization]) {
  const METADATA_URI = 'uri';
  const METADATA_HASH = '0x2a00000000000000000000000000000000000000000000000000000000000000';
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

  const lotsOfZEP = new BigNumber('10e18');
  const minStake = new BigNumber(10);
  const stakeAmount = minStake.times(2);

  beforeEach('TPL setup', async function () {
    // Initialize Jurisdiction
    this.jurisdiction = await BasicJurisdiction.new({ from: jurisdictionOwner });
    const initializeJurisdictionData = encodeCall('initialize', ['address'], [jurisdictionOwner])
    await this.jurisdiction.sendTransaction({ data: initializeJurisdictionData })

    // Initialize ZEPToken
    const attributeID = 0;
    this.token = await ZEPToken.new();
    const initializeZepData = encodeCall('initialize', ['address', 'address', 'uint256'], [tokenOwner, this.jurisdiction.address, attributeID]);
    await this.token.sendTransaction({ data: initializeZepData });

    // Initialize Validator
    this.validator = await OrganizationsValidator.new();
    const initializeValidatorData = encodeCall('initialize', ['address', 'uint256', 'address'], [this.jurisdiction.address, attributeID, validatorOwner]);
    await this.validator.sendTransaction({ data: initializeValidatorData });

    await this.jurisdiction.addValidator(this.validator.address, "ZEP Validator", { from: jurisdictionOwner });
    await this.jurisdiction.addAttributeType(attributeID, "can receive", { from: jurisdictionOwner });
    await this.jurisdiction.addValidatorApproval(this.validator.address, attributeID, { from: jurisdictionOwner });
    await this.validator.addOrganization(organization, 100, "ZEP Org", { from: validatorOwner });
    await this.validator.issueAttribute(tokenOwner, { from: organization });
    await this.validator.issueAttribute(developer, { from: organization });
    await this.token.transfer(developer, lotsOfZEP, { from: tokenOwner });
    this.vouching = await Vouching.new({ from: vouchingOwner });
    await this.vouching.initialize(minStake, this.token.address, { from: vouchingOwner });
    await this.validator.issueAttribute(this.vouching.address, { from: organization });
    await this.token.approve(this.vouching.address, lotsOfZEP, { from: developer });
  });

  beforeEach('dependencies setup', async function () {
    this.dependencyAddress = (await DependencyMock.new()).address;
  });

  describe('initialize', function () {
    it('stores the token address', async function () {
      (await this.vouching.token()).should.equal(this.token.address);
    });

    it('stores the minimum stake', async function () {
      (await this.vouching.minimumStake()).should.be.bignumber.equal(minStake);
    });

    it('requires a non-null token', async function () {
      const vouching = await Vouching.new({ from: vouchingOwner });
      await assertRevert(vouching.initialize(minStake, ZERO_ADDRESS, { from: vouchingOwner }));
    });
  });

  describe('register', function () {
    const from = developer;

    it('reverts when initial stake is less than the minimum', async function () {
      await assertRevert(this.vouching.register(this.dependencyAddress, minStake.minus(1), METADATA_URI, METADATA_HASH, { from }));
    });

    it('reverts for zero dependency address', async function () {
      await assertRevert(this.vouching.register(ZERO_ADDRESS, minStake, METADATA_URI, METADATA_HASH, { from }));
    });

    xit('reverts for a non-contract address', async function () {
      await assertRevert(this.vouching.register(nonContractAddress, minStake, METADATA_URI, METADATA_HASH, { from }));
    });

    it('transfers the initial stake tokens to the vouching contract', async function () {
      const initialBalance = await this.token.balanceOf(this.vouching.address);
      await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });

      const currentBalance = await this.token.balanceOf(this.vouching.address);
      currentBalance.should.be.bignumber.equal(initialBalance.plus(stakeAmount));
    });

    it('stores the created dependency', async function () {
      const result = await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });
      const id = result.logs[0].args.id;

      const addr = await this.vouching.vouched(id);
      addr.should.equal(this.dependencyAddress);

      const owner = await this.vouching.owner(id);
      owner.should.equal(developer);

      const amount = await this.vouching.vouchedAmount(id, developer);
      amount.should.be.bignumber.equal(stakeAmount);

      const totalAmount = await this.vouching.totalVouched(id);
      totalAmount.should.be.bignumber.equal(stakeAmount);
    });

    it('emits a Registered event', async function () {
      const result = await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });

      const event = assertEvent.inLogs(result.logs, 'Registered')
      event.args.id.should.be.bignumber.eq(0)
      event.args.vouched.should.be.eq(this.dependencyAddress)
      event.args.owner.should.be.eq(developer)
      event.args.amount.should.be.bignumber.eq(stakeAmount)
      event.args.metadataURI.should.be.eq(METADATA_URI)
      event.args.metadataHash.should.be.eq(METADATA_HASH)
    });
  });

  describe('vouch', function () {
    const from = developer;

    beforeEach('register a dependency', async function () {
      const result = await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });
      this.id = result.logs[0].args.id
    });

    it('reverts when caller is not the dependency\'s owner', async function () {
      await assertRevert(this.vouching.vouch(this.id, stakeAmount, { from: vouchingOwner }));
    });

    it('transfers stake amount of tokens from sender to vouching contract', async function () {
      const vouchingInitBalance = await this.token.balanceOf(this.vouching.address);
      const devInitBalance = await this.token.balanceOf(developer);

      await this.vouching.vouch(this.id, stakeAmount, { from });

      (await this.token.balanceOf(developer)).should.be.bignumber.equal(devInitBalance.minus(stakeAmount));
      (await this.token.balanceOf(this.vouching.address)).should.be.bignumber.equal(vouchingInitBalance.plus(stakeAmount));
    });

    it('adds the amount vouched to the existing dependency stake', async function () {
      const initialStake = await this.vouching.vouchedAmount(this.id, developer);

      await this.vouching.vouch(this.id, stakeAmount, { from });
      await this.vouching.vouch(this.id, stakeAmount, { from });

      const vouchedAmount = await this.vouching.vouchedAmount(this.id, developer);
      vouchedAmount.should.be.bignumber.equal(initialStake.plus(stakeAmount.times(2)));
    });

    it('emits Vouched event', async function () {
      const result = await this.vouching.vouch(this.id, stakeAmount, { from });

      const event = assertEvent.inLogs(result.logs, 'Vouched')
      event.args.id.should.be.bignumber.eq(this.id)
      event.args.sender.should.be.eq(developer)
      event.args.amount.should.be.bignumber.eq(stakeAmount)
    });
  });

  describe('unvouch', function () {
    const from = developer;
    const safeUnstakeAmount = stakeAmount.minus(minStake);

    beforeEach('register a dependency', async function () {
      const result = await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });
      this.id = result.logs[0].args.id
    });

    it('reverts when caller is not the dependency\'s owner', async function () {
      await assertRevert(this.vouching.unvouch(this.id, safeUnstakeAmount, { from: vouchingOwner }));
    });

    it('reverts when the remaining stake amount is less than the minimum', async function () {
      await assertRevert(this.vouching.unvouch(this.id, safeUnstakeAmount.plus(1), { from }));
    });

    it('reverts when the unvouched amount is greater than current stake', async function () {
      await assertRevert(this.vouching.unvouch(this.id, stakeAmount.plus(1), { from }));
    });

    it('extracts the unvouched amount from the dependency\'s stake', async function () {
      const initDependencyStake = await this.vouching.vouchedAmount(this.id, developer);

      await this.vouching.unvouch(this.id, safeUnstakeAmount, { from });

      const vouchedAmount = await this.vouching.vouchedAmount(this.id, developer);
      vouchedAmount.should.be.bignumber.equal(initDependencyStake.minus(safeUnstakeAmount));
    });

    it('transfers the unvouched amount of tokens to the dependency\'s owner', async function () {
      const vouchingInitBalance = await this.token.balanceOf(this.vouching.address);
      const devInitBalance = await this.token.balanceOf(developer);

      await this.vouching.unvouch(this.id, safeUnstakeAmount, { from });

      (await this.token.balanceOf(developer)).should.be.bignumber.equal(devInitBalance.plus(safeUnstakeAmount));
      (await this.token.balanceOf(this.vouching.address)).should.be.bignumber.equal(vouchingInitBalance.minus(safeUnstakeAmount));
    });

    it('emits Unvouched event', async function () {
      const result = await this.vouching.unvouch(this.id, safeUnstakeAmount, { from });

      const event = assertEvent.inLogs(result.logs, 'Unvouched')
      event.args.id.should.be.bignumber.eq(this.id)
      event.args.sender.should.be.eq(developer)
      event.args.amount.should.be.bignumber.eq(safeUnstakeAmount)
    });
  });

  xdescribe('transferOwnership', function () {
    const from = developer;

    beforeEach('register a dependency', async function () {
      const result = await this.vouching.register(this.dependencyAddress, stakeAmount, METADATA_URI, METADATA_HASH, { from });
      this.id = result.logs[0].args.id;
    });

    it('reverts when caller is not the dependency\'s owner', async function () {
      await assertRevert(this.vouching.transferOwnership(this.id, transferee, { from: vouchingOwner }));
    });

    it('reverts for null new owner address', async function () {
      await assertRevert(this.vouching.transferOwnership(this.id, ZERO_ADDRESS, { from }));
    });

    it('transfers the dependency\'s ownership to a given address', async function () {
      const result = await this.vouching.transferOwnership(this.id, transferee, { from });

      (await this.vouching.owner(this.id)).should.equal(transferee);
      assertEvent.inLogs(result.logs, 'OwnershipTransferred', { oldOwner: developer, newOwner: transferee });
    });
  });
});
