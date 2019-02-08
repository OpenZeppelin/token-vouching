#! /usr/bin/env node

import log from '../../helpers/log'
import parseArgs from 'minimist'
import { runWithTruffle } from 'zos'
import { register, registerAndTransfer } from '../scripts/register'

const params = parseArgs(process.argv.slice(2), { string: ['address', 'amount', 'uri', 'hash', 'owner', 'from'], boolean: 'yes', alias: { y: 'yes' } })
const { address, amount, uri, hash, owner, network, from, yes } = params

if (!address) log.error('Please specify the address of the entry to be registered using --address=<addr>.')
if (!amount)  log.error('Please specify the amount of ZEP tokens to be vouched for the new entry using --amount=<amount>.')
if (!uri)     log.error('Please specify the metadata URI of the entry to be registered using --uri=<uri>.')
if (!hash)    log.error('Please specify the metadata hash of the entry to be registered using --hash=<hash>.')
if (!network) log.error('Please specify a network using --network=<network>.')
if (!from)    log.error('Please specify a sender address using --from=<addr>.')

if (address && amount && uri && hash && network && from) {
  runWithTruffle(options => owner
    ? registerAndTransfer(address, amount, uri, hash, !yes, owner, options)
    : register(address, amount, uri, hash, !yes, options), { network, from })
    .then(console.log)
    .catch(console.error)
}
