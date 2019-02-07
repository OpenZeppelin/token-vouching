import log from '../../helpers/log'
import readline from 'readline'

import { Contracts } from 'zos-lib'
import { fetchVouching } from '../contracts/fetch'
import { fetchZepToken } from '../../2.0/contracts/fetch'

export async function register(address, amount, metadataURI, metadataHash, prompt, { network, txParams }) {
  const vouching = fetchVouching(network)
  const zepToken = fetchZepToken(network)
  const minimumStake = await vouching.minimumStake()
  if (minimumStake.gt(amount)) return log.error(` ✘ Registering amount (${amount} ZEP) must be greater than or equal to the minimum stake ${minimumStake}`)
  if (prompt) await promptOrExit(address, amount, metadataURI, metadataHash)

  try {
    await zepToken.approve(vouching.address, amount, txParams)
    log.info(` ✔ Approved ${amount} ZEP from ${txParams.from} to vouching contract ${vouching.address}`)

    const receipt = await vouching.register(address, amount, metadataURI, metadataHash, txParams)
    const id = receipt.logs[0].args.id
    log.info(` ✔ Vouching entry registered with ID ${id}`)

    return id
  } catch (error) {
    throwError('Could not register entry', error)
  }
}

export async function registerAndTransfer(address, amount, metadataURI, metadataHash, prompt, owner, { network, txParams }) {
  try {
    const id = await register(address, amount, metadataURI, metadataHash, prompt, { network, txParams })
    const vouching = fetchVouching(network)
    await vouching.transferOwnership(id, owner, txParams)
    log.info(` ✔ Ownership of entry with ID ${id} transferred to ${owner}`)

    return id
  } catch (error) {
    throwError(`Could register and transfer entry`, error)
  }
}

async function promptOrExit(address, amount, metadataURI, metadataHash) {
  const response = await new Promise(resolve => {
    const prompt = readline.createInterface({ input: process.stdin, output: process.stdout })
    prompt.question(`You're about to register the following entry:\n - Address: ${address}\n - Amount: ZEP ${amount}\n - Metadata URI: ${metadataURI}\n - Metadata hash: ${metadataHash}\n\nDo you want to proceed? [y/n] `, answer => {
      prompt.close()
      resolve(answer)
    })
  })
  if (!['y', 'Y', 'n', 'N'].includes(response)) return promptOrExit(address, amount, metadataURI, metadataHash)
  if (response === 'n' || response === 'N') process.exit(0)
}

function throwError(msg, error = undefined) {
  log.error(` ✘ ${msg}`)
  if (error) throw error
  else throw Error(msg)
}
