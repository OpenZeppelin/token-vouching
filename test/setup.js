process.env.NODE_ENV = 'test'

require('chai')
  .use(require('chai-bignumber')(web3.BigNumber))
  .should();
