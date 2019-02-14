import { utils } from 'web3'

export const bn = x => utils.toBN(x)
export const zep = x => bn(x).mul(bn(10).pow(bn(18)))
export const pct = x => bn(x).mul(bn(10).pow(bn(16)))