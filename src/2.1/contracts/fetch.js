import { files } from 'zos'
import { Contracts } from 'zos-lib'
import validateAddress from '../../helpers/validateAddress'
import { fetchNetworkFile } from '../../2.0/contracts/fetch'

export function fetchVouching(network) {
  const vouchingProxies = fetchNetworkFile(network)._proxiesOf('zos-vouching/Vouching')
  if (vouchingProxies.length > 0) {
    const vouchingAddress = vouchingProxies[vouchingProxies.length - 1].address
    if (validateAddress(vouchingAddress)) {
      const Vouching = Contracts.getFromLocal('Vouching')
      return Vouching.at(vouchingAddress)
    }
  }
}
