import { files } from 'zos'
import { Contracts } from 'zos-lib'
import validateAddress from '../../helpers/validateAddress'

export function fetchNetworkFile(network) {
  const { ZosPackageFile } = files
  const packageFile = new ZosPackageFile()
  return packageFile.networkFile(network)
}

export function fetchJurisdiction(network) {
  const jurisdictionProxies = fetchNetworkFile(network)._proxiesOf('tpl-contracts-eth/BasicJurisdiction')
  if (jurisdictionProxies.length > 0) {
    const jurisdictionAddress = jurisdictionProxies[jurisdictionProxies.length - 1].address
    if (validateAddress(jurisdictionAddress)) {
      const BasicJurisdiction = Contracts.getFromNodeModules('tpl-contracts-eth', 'BasicJurisdiction')
      return BasicJurisdiction.at(jurisdictionAddress)
    }
  }
}

export function fetchZepToken(network) {
  const zepTokenProxies = fetchNetworkFile(network)._proxiesOf('zos-vouching/ZEPToken')
  if (zepTokenProxies.length > 0) {
    const zepTokenAddress = zepTokenProxies[zepTokenProxies.length - 1].address
    if (validateAddress(zepTokenAddress)) {
      const ZEPToken = Contracts.getFromLocal('ZEPToken')
      return ZEPToken.at(zepTokenAddress)
    }
  }
}

export function fetchVouching(network) {
  const vouchingProxies = fetchNetworkFile(network)._proxiesOf('zos-vouching/Vouching')
  if (vouchingProxies.length > 0) {
    const vouchingAddress = vouchingProxies[vouchingProxies.length - 1].address
    if (validateAddress(vouchingAddress)) {
      const Vouching = Contracts.getFromLocal('OldVouching')
      return Vouching.at(vouchingAddress)
    }
  }
}

export function fetchValidator(network) {
  const validatorProxies = fetchNetworkFile(network)._proxiesOf('tpl-contracts-eth/OrganizationsValidator')
  if (validatorProxies.length > 0) {
    const validatorAddress = validatorProxies[validatorProxies.length - 1].address
    if (validateAddress(validatorAddress)) {
      const OrganizationsValidator = Contracts.getFromNodeModules('tpl-contracts-eth', 'OrganizationsValidator')
      return OrganizationsValidator.at(validatorAddress)
    }
  }
}
