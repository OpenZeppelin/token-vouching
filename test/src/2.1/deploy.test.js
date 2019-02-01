require('../../setup')

import log from '../../../src/helpers/log'
import { files } from 'zos'
import { FileSystem as fs } from 'zos-lib'
import { verifyVouching as verifyNewVouching } from '../../../src/2.1/scripts/verify'
import { default as deploy1 } from '../../../src/2.0/scripts/deploy'
import { default as deploy2 } from '../../../src/2.1/scripts/deploy'
import { verifyAppSetup, verifyJurisdiction, verifyOrganizationsValidator, verifyTPLConfiguration, verifyZEPToken, verifyVouching as verifyOldVouching } from "../../../src/2.0/scripts/verify";

const { ZosPackageFile } = files

contract('deploy 2.1', function([_, owner]) {
  log.silent(true)
  const network = 'test'
  const txParams = { from: owner }
  const options = { network, txParams }

  it('deploys a new vouching instance', async function() {
    const packageFile = new ZosPackageFile()

    await deploy1(options)
    let networkFile = packageFile.networkFile(network)

    assert(await verifyAppSetup(networkFile), 'deploy 2.0 should configure a ZeppelinOS App correctly')
    assert(await verifyJurisdiction(networkFile, txParams), 'deploy 2.0 should create a Jurisdiction instance correctly')
    assert(await verifyZEPToken(networkFile, txParams), 'deploy 2.0 should create a ZEP Token instance correctly')
    assert(await verifyOldVouching(networkFile, txParams), 'deploy 2.0 should create an old Vouching instance correctly')
    assert(await verifyOrganizationsValidator(networkFile, txParams), 'deploy 2.0 should create a Validator instance correctly')
    assert(await verifyTPLConfiguration(networkFile, txParams), 'deploy 2.0 should configure TPL correctly')

    await deploy2(options)
    networkFile = packageFile.networkFile(network)

    assert(await verifyNewVouching(networkFile, txParams), 'deploy 2.1 should create a new Vouching instance correctly')
  })

  after('remove zos test files', function () {
    fs.remove('zos.test.json')
    fs.remove('zos.summary.test.json')
  })
})
