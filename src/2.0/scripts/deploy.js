import { scripts, stdout } from 'zos'
import { OUTPUT_FILE } from '../constants'

import log from '../../helpers/log'
import save from '../contracts/save'
import create from '../contracts/create'
import configureTPL from '../contracts/configureTPL'

const { add, push, session } = scripts

export default async function deploy(options) {
  const oneDay = 60 * 60 * 24
  session({ expires: oneDay, ...options })
  stdout.silent(false)
  const vouchingData = { alias: 'Vouching', name: 'OldVouching' }
  const zepTokenData = { alias: 'ZEPToken', name: 'ZEPToken' }
  const contractsData = [vouchingData, zepTokenData]
  add({ contractsData })

  log.base(`Pushing vouching app with options ${JSON.stringify(options, null, 2)}...`)
  const deployDependencies = true // ZeppelinOS only deploys requested packages if those are not deployed
  await push({ deployDependencies, ...options })
  const { app, jurisdiction, validator, zepToken, vouching } = await create(options)
  await configureTPL(jurisdiction, validator, options)
  save(OUTPUT_FILE(options.network), app, jurisdiction, zepToken, validator, vouching)
}
