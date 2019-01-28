import { scripts, stdout } from 'zos'
import { OUTPUT_FILE } from '../constants'

import log from '../helpers/log'
import save from '../contracts/save'
import create from '../contracts/create'
import configureTPL from '../contracts/configureTPL'

const { push, session } = scripts

export default async function deploy(options) {
  const oneDay = 60 * 60 * 24
  session({ expires: oneDay, ...options })
  log.base(`Pushing vouching app with options ${JSON.stringify(options, null, 2)}...`)
  const deployDependencies = true // ZeppelinOS only deploys requested packages if those are not deployed
  await push({ deployDependencies, ...options })
  stdout.silent(true)
  const { app, jurisdiction, validator, zepToken, vouching } = await create(options)
  await configureTPL(jurisdiction, validator, options)
  save(OUTPUT_FILE(options.network), app, jurisdiction, zepToken, validator, vouching)
}
