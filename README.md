# Squeek Relay

squeekchain-project: 645a5272-0b43-4f3f-9707-9f002456afea

An interactive Squeekchain game concept for the Genesis build board.

The app is a buildless static site in `dist/index.html`. It polls `https://api.squeekchain.com/v1/status` every five seconds and derives the game state from the public measurement fields: a relay opens only when the wheel reports fresh movement, and closes when the API reports idle. If telemetry is stale or unavailable, actions are disabled rather than simulated.

The live gasless relay contract is deployed on Sepolia at `0xc034A1C95701bc6701110FE392a0ADb61244ac4C` (deployment transaction `0xb63a1aeb38d31313d269f45f079d6a9a2f718cbc401e4b0568a3393a845a35c4`). Players sign EIP-712 intents in their wallet; the relay pays gas and stores score receipts onchain. The earlier player-pays contract is retained as `legacyPlayerPaysContract` in `deployments/sepolia.json` for reference only.

The hosted relay worker verifies fresh wheel telemetry, opens the current round when the first player joins, and submits the signed join/cash-out transaction. Its private keeper key is configured only as a hosting secret; no key is stored in this repository. For local operations, `scripts/relay-keeper.sh` remains available but is not needed by the public game.

## Deployment

- Frontend: publish `dist/` with any static host, including Vercel.
- Relay worker: deploy `relayer-site/` as an edge worker and set `KEEPER_PRIVATE_KEY`, `SEPOLIA_RPC_URL`, and `RELAY_CONTRACT` as provider secrets/environment variables.
- The browser only needs the public frontend and relay URL; players never need Sepolia ETH.

## Safety

The repository intentionally excludes `.env` files, hosting credentials, generated worker bundles, dependency folders, and local Site metadata. Run the local validation scripts before publishing changes.
