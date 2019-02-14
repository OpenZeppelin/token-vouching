import log from '../../helpers/log'
import { scripts, stdout } from 'zos'
import { Contracts, ABI } from 'zos-lib'
import { verifyVouchingHasTplAttribute } from './verify'
import { VOUCHING_MIN_STAKE, VOUCHING_APPEAL_FEE } from '../../2.1/constants'
import { fetchNetworkFile, fetchValidator, fetchVouching, fetchZepToken } from '../../2.0/contracts/fetch'

const { add, push, session, create } = scripts
const { buildCallData, callDescription } = ABI

export default async function deploy(options) {
  const oneDay = 60 * 60 * 24
  session({ expires: oneDay, ...options })
  add({ contractsData: [{ alias: 'Vouching', name: 'Vouching' }] })
  log.base(`Pushing new vouching contract with options ${JSON.stringify(options, null, 2)}...`)
  await push({ force: true, ...options }) // We are forcing here since we are overriding the storage layout
  stdout.silent(true)
  log.base('\n\n--------------------------------------------------------------------\n\n')

  const { network } = options
  const oldVouching = fetchVouching(network)
  if (oldVouching) {
    log.warn(`\n\nDropping old Vouching instance ${oldVouching.address}...`)
    const networkFile = fetchNetworkFile(network)
    networkFile.removeProxy('zos-vouching', 'Vouching', oldVouching.address)
    networkFile.write()
  }

  const zepToken = fetchZepToken(network)
  if (zepToken) log.info(` ✔ Using ZEPToken instance at ${zepToken.address}`)
  else throwError(`Could not found a ZEPToken instance in zos ${network} file`)

  const validator = fetchValidator(network)
  if (validator) log.info(` ✔ Using Validator instance at ${validator.address}`)
  else throwError(`Could not found a Validator instance in zos ${network} file`)

  const appealsResolver = options.txParams.from
  printVouching(appealsResolver, zepToken)
  const vouching = await createVouching(zepToken, appealsResolver, options)
  await issueTransferAttributeToVouching(zepToken, validator, vouching, options)
}

async function createVouching(zepToken, appealsResolver, { network, txParams }) {
  const packageName = 'zos-vouching'
  const contractAlias = 'Vouching'
  const initMethod = 'initialize'
  const initArgs = [zepToken.address, VOUCHING_MIN_STAKE, VOUCHING_APPEAL_FEE, appealsResolver]
  try {
    const vouching = await create({ packageName, contractAlias, initMethod, initArgs, network, txParams })
    log.info(` ✔ Vouching created at ${vouching.address}`)
    return vouching
  } catch (error) {
    const Vouching = Contracts.getFromLocal(contractAlias)
    const { method } = buildCallData(Vouching, initMethod, initArgs);
    log.error(` ✘ Could not create Vouching instance by calling ${callDescription(method, initArgs)}`)
    throw error
  }
}

async function issueTransferAttributeToVouching(zepToken, validator, vouching, { txParams }) {
  log.base(`\nIssuing TPL attribute to Vouching instance ${vouching.address}...`)
  try {
    if (await verifyVouchingHasTplAttribute(zepToken, vouching, false)) {
      log.warn(` ✔ Vouching instance already has TPL attribute`)
    }
    else {
      const { tx } = await validator.methods.issueAttribute(vouching.address).send(txParams)
      log.info(` ✔ TPL attribute issued to vouching instance: ${tx}`)
    }
  } catch (error) {
    throwError('Could not issue TPL attribute to vouching instance', error)
  }
}

function printVouching(appealsResolver, zepToken = undefined) {
  log.base('\n--------------------------------------------------------------------\n\n')
  log.base(`Creating new Vouching instance with: `)
  log.base(` - Appeals resolver:  ${appealsResolver}`)
  log.base(` - Appeal fee:        ${VOUCHING_APPEAL_FEE}`)
  log.base(` - Minimum stake:     ${VOUCHING_MIN_STAKE}`)
  log.base(` - ZEP token:         ${zepToken ? zepToken.address : '[a new instance to be created]'}\n`)
}

function throwError(msg, error = undefined) {
  log.error(` ✘ ${msg}`)
  if (error) throw error
  else throw Error(msg)
}
