export default seconds => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync(
      {
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [seconds],
        id: new Date().getTime()
      },
      error => error ? reject(error) : resolve()
    )
  })
}
