require('../setup')

import { utils } from 'web3'
import { Contracts, encodeCall, assertRevert } from 'zos-lib'

const ZEPToken = artifacts.require('ZEPToken');
const BasicJurisdiction = Contracts.getFromNodeModules('tpl-contracts-eth', 'BasicJurisdiction')
const OrganizationsValidator = Contracts.getFromNodeModules('tpl-contracts-eth', 'OrganizationsValidator')

contract('ZEPToken', ([ _, tokenOwner, another, jurisdictionOwner, validatorOwner, zeppelin, sender, recipient ]) => {
  const receiveTokensAttributeID = 999

  beforeEach('initialize jurisdiction', async function () {
    this.jurisdiction = await BasicJurisdiction.new()
    const initializeJurisdictionData = encodeCall('initialize', ['address'], [jurisdictionOwner])
    await this.jurisdiction.sendTransaction({ data: initializeJurisdictionData })
  })

  beforeEach('initialize ZEP token', async function () {
    this.zepToken = await ZEPToken.new()
    const initializeData = encodeCall('initialize', ['address', 'address', 'uint256'], [tokenOwner, this.jurisdiction.address, receiveTokensAttributeID])
    await this.zepToken.sendTransaction({ data: initializeData })
  });

  it('has a name', async function () {
    const name = await this.zepToken.methods.name().call();
    name.should.be.equal('ZEP Token');
  });

  it('has a symbol', async function () {
    const symbol = await this.zepToken.methods.symbol.call();
    symbol.should.be.equal('ZEP');
  });

  it('has an amount of decimals', async function () {
    const decimals = await this.zepToken.methods.decimals().call();
    decimals.should.be.bignumber.equal(18);
  });

  it('has the correct total supply', async function () {
    const totalZEP = utils.toBN(100000000).mul(utils.toBN(10).pow(utils.toBN(18)))
    (await this.zepToken.totalSupply({ from: another })).should.be.bignumber.equal(totalZEP);
  })

  it('can be paused by creator', async function () {
    await this.zepToken.methods.pause().send({ from: tokenOwner });
  })

  it('cannot be paused by anybody', async function () {
    await assertRevert(this.zepToken.methods.pause.send({ from: another }));
  })

  describe('TPL', function () {
    const amount = '5e18'

    beforeEach('initialize and approve validator', async function () {
      this.validator = await OrganizationsValidator.new()
      const initializeValidatorData = encodeCall('initialize', ['address', 'uint256', 'address'], [this.jurisdiction.address, receiveTokensAttributeID, validatorOwner])
      await this.validator.sendTransaction({ data: initializeValidatorData })

      await this.jurisdiction.methods.addValidator(this.validator.address, "ZEP Validator").send({ from: jurisdictionOwner })
      await this.jurisdiction.methods.addAttributeType(receiveTokensAttributeID, "can receive").send({ from: jurisdictionOwner })
      await this.jurisdiction.methods.addValidatorApproval(this.validator.address, receiveTokensAttributeID).send({ from: jurisdictionOwner })
      await this.validator.methods.addOrganization(zeppelin, 100, "ZEP Org").send({ from: validatorOwner })
    })

    describe('when the sender is allowed to receive tokens', function () {
      beforeEach(async function () {
        await this.validator.methods.issueAttribute(sender).send({ from: zeppelin })
      })

      describe('when the sender has tokens', function () {
        beforeEach(async function () {
          await this.zepToken.methods.transfer(sender, amount).send({ from: tokenOwner })
        })

        describe('when the recipient is not allowed to receive tokens', function () {
          assertItCannotReceiveTokens()
        })

        describe('when the recipient is allowed to receive tokens', function () {
          beforeEach(async function () {
            await this.validator.methods.issueAttribute(recipient).send({ from: zeppelin })
          })

          assertItCanReceiveTokens()

          describe('when the recipient\'s permission to receive tokens is revoked', function () {
            beforeEach(async function () {
              await this.validator.methods.revokeAttribute(recipient).send({ from: zeppelin })
            })

            assertItCannotReceiveTokens()
          })

          describe('when the validator approval is removed', function () {
            beforeEach(async function () {
              await this.jurisdiction.methods.removeValidatorApproval(this.validator.address, receiveTokensAttributeID).send({ from: jurisdictionOwner })
            })

            assertItCannotReceiveTokens()
          })
        })

        describe('when the sender\'s permission to receive tokens is revoked', function () {
          describe('when the recipient is not allowed to receive tokens', function () {
            assertItCannotReceiveTokens()
          })

          describe('when the recipient is allowed to receive tokens', function () {
            beforeEach(async function () {
              await this.validator.methods.issueAttribute(recipient).send({ from: zeppelin })
            })

            assertItCanReceiveTokens()

            describe('when the recipient\'s permission to receive tokens is revoked', function () {
              beforeEach(async function () {
                await this.validator.methods.revokeAttribute(recipient).send({ from: zeppelin })
              })

              assertItCannotReceiveTokens()
            })

            describe('when the validator approval is removed', function () {
              beforeEach(async function () {
                await this.jurisdiction.methods.removeValidatorApproval(this.validator.address, receiveTokensAttributeID).send({ from: jurisdictionOwner })
              })

              assertItCannotReceiveTokens()
            })
          })
        })
      })
    })

    function assertItCannotReceiveTokens() {
      it('cannot receive tokens', async function () {
        assert.equal(await this.zepToken.methods.canReceive(recipient).call(), false)
        await assertRevert(this.zepToken.methods.transfer(recipient, amount).send({ from: sender }))
      })

      it('cannot receive tokens from', async function () {
        await this.zepToken.methods.approve(recipient, amount).send({ from: sender })

        assert.equal(await this.zepToken.methods.canReceive(recipient).call(), false)
        await assertRevert(this.zepToken.methods.transferFrom(sender, recipient, amount).send({ from: recipient }))
      })
    }

    function assertItCanReceiveTokens() {
      it('can receive tokens', async function () {
        assert(await this.zepToken.methods.canReceive(recipient).call())
        await this.zepToken.methods.transfer(recipient, amount).send({ from: sender })

        assert((await this.zepToken.methods.balanceOf(recipient).call()).eq(amount))
      })

      it('can receive tokens from', async function () {
        await this.zepToken.methods.approve(recipient, amount).send({ from: sender })

        assert(await this.zepToken.methods.canReceive(recipient).call())
        await this.zepToken.methods.transferFrom(sender, recipient, amount).send({ from: recipient })

        assert((await this.zepToken.balanceOf(recipient)).eq(amount))
      })
    }
  })
});
