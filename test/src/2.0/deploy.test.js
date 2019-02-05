require('../../setup')

import { files } from 'zos'
import { FileSystem as fs } from 'zos-lib'
import log from '../../../src/helpers/log'
import deploy from '../../../src/2.0/scripts/deploy'
import { verifyAppSetup, verifyJurisdiction, verifyTPLConfiguration, verifyVouching, verifyZEPToken, verifyOrganizationsValidator } from '../../../src/2.0/scripts/verify'

const { ZosPackageFile } = files

contract('deploy 2.0', function([_, owner]) {
  log.silent(true)
  const network = 'test'
  const txParams = { from: owner }
  const options = { network, txParams }

  before('deploy', async function () {
    this.packageFile = new ZosPackageFile()
    fs.copy(this.packageFile.fileName, `${this.packageFile.fileName}.tmp`)
    await deploy(options)
    this.networkFile = this.packageFile.networkFile(network)
  })

  it('setups a zeppelin os app', async function() {
    assert(await verifyAppSetup(this.networkFile))
  })

  it('deploys a basic jurisdiction', async function() {
    assert(await verifyJurisdiction(this.networkFile, txParams))
  })

  it('deploys a ZEP token', async function() {
    assert(await verifyZEPToken(this.networkFile, txParams))
  })

  it('deploys a vouching contract', async function() {
    assert(await verifyVouching(this.networkFile, txParams))
  })

  it('deploys an Organizations Validator', async function() {
    assert(await verifyOrganizationsValidator(this.networkFile, txParams))
  })

  it('configures TPL', async function() {
    assert(await verifyTPLConfiguration(this.networkFile, txParams))
  })

  after('remove zos test files', function () {
    fs.remove('zos.test.json')
    fs.remove('zos.summary.test.json')
    fs.copy(`${this.packageFile.fileName}.tmp`, this.packageFile.fileName)
    fs.remove(`${this.packageFile.fileName}.tmp`)
  })
})
