import log from '../../helpers/log'
import { scripts } from 'zos'
import { Contracts, ABI } from 'zos-lib'
import { ZEPTOKEN_ATTRIBUTE_ID, VOUCHING_MIN_STAKE } from '../constants'
import { printJurisdiction, printValidator, printVouching, printZepToken } from './print'
import { fetchJurisdiction, fetchNetworkFile, fetchValidator, fetchVouching, fetchZepToken } from './fetch'

const { create } = scripts
const { buildCallData, callDescription } = ABI

export default async function createContracts({ network, txParams }) {
  const owner = txParams.from

  const jurisdiction = await createBasicJurisdiction(owner, network, txParams)
  const zepToken = await createZEPToken(owner, jurisdiction, network, txParams)
  const vouching = await createVouching(zepToken, network, txParams)
  const validator = await createOrganizationsValidator(owner, jurisdiction, network, txParams)
  const app = fetchNetworkFile(network).app
  return { app, jurisdiction, validator, zepToken, vouching }
}

export async function createBasicJurisdiction(owner, network, txParams) {
  printJurisdiction(owner)
  const jurisdiction = fetchJurisdiction(network)
  if (jurisdiction) {
    log.warn(` -  Reusing BasicJurisdiction instance at ${jurisdiction.address}`)
    return jurisdiction
  }

  const packageName = 'tpl-contracts-eth'
  const contractAlias = 'BasicJurisdiction'
  const initMethod = 'initialize'
  const initArgs = [owner]
  try {
    const basicJurisdiction = await create({ packageName, contractAlias, initMethod, initArgs, network, txParams })
    log.info(` ✔ BasicJurisdiction created at ${basicJurisdiction.address}`)
    return basicJurisdiction
  } catch (error) {
    const BasicJurisdiction = Contracts.getFromNodeModules(packageName, contractAlias)
    const { method } = buildCallData(BasicJurisdiction, initMethod, initArgs);
    log.error(` ✘ Could not create basic jurisdiction by calling ${callDescription(method, initArgs)}`)
    throw error
  }
}

export async function createZEPToken(owner, basicJurisdiction, network, txParams) {
  printZepToken(owner, basicJurisdiction)
  const zepToken = fetchZepToken(network)
  if (zepToken) {
    log.warn(` -  Reusing ZEPToken instance at ${zepToken.address}`)
    return zepToken
  }

  const packageName = 'zos-vouching'
  const contractAlias = 'ZEPToken'
  const initMethod = 'initialize'
  const initArgs = [owner, basicJurisdiction.address, ZEPTOKEN_ATTRIBUTE_ID]
  try {
    const zepToken = await create({ packageName, contractAlias, initMethod, initArgs, network, txParams })
    log.info(` ✔ ZEPToken created at ${zepToken.address}`)
    return zepToken
  } catch (error) {
    const ZEPToken = Contracts.getFromLocal(contractAlias)
    const { method } = buildCallData(ZEPToken, initMethod, initArgs);
    log.error(` ✘ Could not create ZEP token by calling ${callDescription(method, initArgs)}`)
    throw error
  }
}

export async function createOrganizationsValidator(owner, basicJurisdiction, network, txParams) {
  printValidator(owner, basicJurisdiction)
  const validator = fetchValidator(network)
  if (validator) {
    log.warn(` -  Reusing Organizations validator instance at ${validator.address}`)
    return validator
  }

  const packageName = 'tpl-contracts-eth'
  const contractAlias = 'OrganizationsValidator'
  const initMethod = 'initialize'
  const initArgs = [basicJurisdiction.address, ZEPTOKEN_ATTRIBUTE_ID, owner]
  try {
    const validator = await create({ packageName, contractAlias, initMethod, initArgs, network, txParams })
    log.info(` ✔ Organizations validator created at ${validator.address}`)
    return validator
  } catch (error) {
    const OrganizationsValidator = Contracts.getFromNodeModules(packageName, contractAlias)
    const { method } = buildCallData(OrganizationsValidator, initMethod, initArgs);
    log.error(` ✘ Could not create Organizations validator by calling ${callDescription(method, initArgs)}`)
    throw error
  }
}

export async function createVouching(zepToken, network, txParams) {
  printVouching(zepToken)
  const vouching = fetchVouching(network)
  if (vouching) {
    log.warn(` -  Reusing Vouching instance at ${vouching.address}`)
    return vouching
  }

  const packageName = 'zos-vouching'
  const contractAlias = 'Vouching'
  const initMethod = 'initialize'
  const initArgs = [VOUCHING_MIN_STAKE, zepToken.address]
  try {
    const vouching = await create({ packageName, contractAlias, initMethod, initArgs, network, txParams })
    log.info(` ✔ Vouching created at ${vouching.address}`)
    return vouching
  } catch (error) {
    const Vouching = Contracts.getFromLocal(contractAlias)
    const { method } = buildCallData(Vouching, initMethod, initArgs);
    log.error(` ✘ Could not create vouching contract by calling ${callDescription(method, initArgs)}`)
    throw error
  }
}
