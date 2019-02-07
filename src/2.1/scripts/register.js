import log from '../../helpers/log'
import readline from 'readline'

import { Contracts } from 'zos-lib'
import { fetchVouching } from '../contracts/fetch'
import { fetchZepToken } from '../../2.0/contracts/fetch'

export async function register(address, amount, metadataURI, metadataHash, prompt, { network, txParams }) {
  if (prompt) await promptOrExit(address, amount, metadataHash, metadataURI)

  const vouching = fetchVouching(network)
  const zepToken = fetchZepToken(network)

  try {
    await zepToken.approve(vouching.address, amount, txParams)
    log.info(` ✔ Approved ZEP ${amount} from ${txParams.from} to vouching contract`)

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
  if (['y', 'Y', 'n', 'N'].includes(response)) return promptOrExit()
  if (response === 'n' || response === 'N') process.exit(0)
  log.base('\n\n')
}

function throwError(msg, error = undefined) {
  log.error(` ✘ ${msg}`)
  if (error) throw error
  else throw Error(msg)
}
