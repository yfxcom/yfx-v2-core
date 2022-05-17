# YFX Contract V2 Core

This repository contains the core smart contracts for the YFX Contract V2 Core Protocol.

## Local deployment

```shell
    ### heco mainnet
    npm install
    hardhat comile
    hardhat run script/deploy_HT.js --network heco
```

## License

The primary license for YFX Contract V2 Core is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE).

However, some files are dual licensed under `GPL-2.0-or-later`:

- All files in `contracts/interface/` may also be licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers).
- Several files in `contracts/library/` may also be licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers).