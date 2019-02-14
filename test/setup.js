import { ZWeb3 } from 'zos-lib'

process.env.NODE_ENV = 'test'

require('chai')
  .use(require('chai-bignumber')(web3.BN))
  .should();

ZWeb3.initialize(web3.currentProvider)
