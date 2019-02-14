require('../../setup')

import log from '../../../src/helpers/log'

import { Contracts, FileSystem as fs } from 'zos-lib'
import { fetchVouching } from '../../../src/2.1/contracts/fetch'
import { VOUCHING_MIN_STAKE } from '../../../src/2.1/constants'
import { default as deploy1 } from '../../../src/2.0/scripts/deploy'
import { default as deploy2 } from '../../../src/2.1/scripts/deploy'
import { register, registerAndTransfer } from '../../../src/2.1/scripts/register'
import { fetchValidator, fetchZepToken } from '../../../src/2.0/contracts/fetch'

contract('register', function([_, entry, registrar, someone]) {
  log.silent(true)
  const network = 'test'
  const txParams = { from: registrar }
  const options = { network, txParams }

  before('deploy', async function () {
    await deploy1(options)
    await deploy2(options)

    const validator = fetchValidator(network)
    await validator.issueAttribute(registrar, txParams)

    this.zepToken = fetchZepToken(network)
  })

  context('when the given amount is lower than the minimum stake', function () {
    const amount = 1

    it('does not register', async function() {
      const id = await register(entry, amount, 'uri', '0x2a', false, options)

      assert.equal(id, undefined)
    })
  })

  context('when the given amount is not lower than the minimum stake', function () {
    const amount = VOUCHING_MIN_STAKE

    it('registers a new entry', async function() {
      await this.zepToken.transfer(registrar, amount, txParams)

      const id = await register(entry, VOUCHING_MIN_STAKE, 'uri', '0x2a', false, options)

      const vouching = fetchVouching(network)
      const [address, owner, metadataURI, metadataHash, minimumStake] = await vouching.methods.getEntry(id).call()

      assert(minimumStake.eq(VOUCHING_MIN_STAKE))
      assert.equal(address, entry)
      assert.equal(owner, registrar)
      assert.equal(metadataURI, 'uri')
      assert.equal(metadataHash, '0x2a00000000000000000000000000000000000000000000000000000000000000')
    })

    it('registers and transfers a new entry', async function() {
      await this.zepToken.methods.transfer(registrar, amount).send(txParams)

      const id = await registerAndTransfer(entry, VOUCHING_MIN_STAKE, 'uri', '0x2a', false, someone, options)

      const vouching = fetchVouching(network)
      const [address, owner, metadataURI, metadataHash, minimumStake] = await vouching.methods.getEntry(id).call()

      assert(minimumStake.eq(VOUCHING_MIN_STAKE))
      assert.equal(address, entry)
      assert.equal(owner, someone)
      assert.equal(metadataURI, 'uri')
      assert.equal(metadataHash, '0x2a00000000000000000000000000000000000000000000000000000000000000')
    })
  })

  after('remove zos test files', function () {
    fs.remove('zos.test.json')
    fs.remove('zos.summary.test.json')
  })
})
