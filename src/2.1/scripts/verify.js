import log from '../../helpers/log'

import { Contracts } from 'zos-lib'
import { fetchVouching } from '../contracts/fetch'
import { fetchZepToken } from '../../2.0/contracts/fetch'
import { VOUCHING_MIN_STAKE, VOUCHING_APPEAL_FEE } from '../constants'

export default async function verify({ network, txParams }) {
  log.info(`Verifying vouching app on network ${ network }...`)
  if (await verifyVouching(network, txParams)) log.info('\n\nVouching instance was deployed and configured successfully!')
  else log.error('\n\nThere was an error while verifying the vouching instance.')
}

export async function verifyVouching(network, txParams) {
  log.base('\n--------------------------------------------------------------------\n')
  log.base('Verifying new Vouching instance...')

  const vouching = fetchVouching(network)
  if (vouching) {
    const token = await vouching.token()
    const minimumStake = await vouching.minimumStake()
    const appealFee = await vouching.appealFee()
    const appealsResolver = await vouching.appealsResolver()

    const zepToken = fetchZepToken(network)
    const zepTokenAddress = zepToken.address
    const tokenMatches = token === zepTokenAddress
    const minimumStakeMatches = minimumStake.eq(VOUCHING_MIN_STAKE)
    const appealFeeMatches = appealFee.eq(VOUCHING_APPEAL_FEE)
    const appealsResolverMatches = appealsResolver === txParams.from

    tokenMatches
      ? log.info (' ✔ Vouching token matches ZEP Token deployed instance')
      : log.error(` ✘ Vouching token ${token} does not match ZEP Token deployed instance ${zepTokenAddress}`)

    minimumStakeMatches
      ? log.info (' ✔ Vouching minimum stake matches requested value')
      : log.error(` ✘ Vouching minimum stake ${minimumStake} does not match requested value, it was expected ${VOUCHING_MIN_STAKE}`)

    appealFeeMatches
      ? log.info (' ✔ Vouching appeal fee matches requested value')
      : log.error(` ✘ Vouching appeal fee ${appealFee} does not match requested value, it was expected ${VOUCHING_APPEAL_FEE}`)

    appealsResolverMatches
      ? log.info (' ✔ Vouching appeals resolver matches requested value')
      : log.error(` ✘ Vouching appeals resolver ${appealsResolver} does not match requested value, it was expected ${txParams.from}`)

    const hasTPLAttribute = await verifyVouchingHasTplAttribute(zepToken, vouching, true)

    return tokenMatches && minimumStakeMatches && appealFeeMatches && appealsResolverMatches && hasTPLAttribute

  }
  else {
    log.error(' ✘ Missing valid instance of Vouching')
    return false
  }
}

export async function verifyVouchingHasTplAttribute(zepToken, vouching, logVerifications = false) {
  const vouchingCanReceive = await zepToken.canReceive(vouching.address)
  if(logVerifications) {
    vouchingCanReceive
      ? log.info (` ✔ Vouching instance has TPL attribute to receive ZEP tokens`)
      : log.error(` ✘ Vouching instance does not have TPL attribute to receive ZEP tokens`)
  }
  return vouchingCanReceive
}
