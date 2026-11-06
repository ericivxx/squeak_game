#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
CONTRACT="${SQUEEK_RELAY_CONTRACT:-0xB01808b1aa482978C0D8Bb4BBAD04653943319eE}"
ENV_FILE="${MINT_BOT_ENV_FILE:-/home/eric/projects/mint_bot/.env}"

set -a
source "$ENV_FILE"
set +a
KEY="${WALLET_MAIN_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
if [[ -z "$KEY" ]]; then echo "missing keeper key" >&2; exit 1; fi

json_field() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let x=JSON.parse(s);for(let k of process.argv[1].split("."))x=x?.[k];console.log(x??"")})' "$1"; }

while true; do
  status="$(curl -fsS --max-time 8 https://api.squeekchain.com/v1/status)" || { sleep 5; continue; }
  freshness="$(printf '%s' "$status" | json_field measurement.freshness)"
  core="$(printf '%s' "$status" | json_field measurement.coreStatus)"
  rpm="$(printf '%s' "$status" | json_field measurement.rpmMilli)"
  last="$(printf '%s' "$status" | json_field oracle.latestClosure.lastRound)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  [[ "$rpm" =~ ^[0-9]+$ ]] || rpm=0
  next=$((last + 1))
  current="$(cast call "$CONTRACT" 'currentRound()(uint256)' --rpc-url "$RPC_URL" | tr -d '[:space:]')"
  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  running=false
  if [[ "$freshness" == "online" && ( "$core" == "RUNNING" || "$core" == "ACTIVE" || "$rpm" -gt 0 ) ]]; then running=true; fi

  if $running && (( current < next )); then
    cast send "$CONTRACT" "openRound(uint256)" "$next" --rpc-url "$RPC_URL" --private-key "$KEY" >/dev/null
  elif ! $running && (( current > 0 )); then
    open="$(cast call "$CONTRACT" 'rounds(uint256)(uint64,uint64,bool)' "$current" --rpc-url "$RPC_URL" | tail -1 | tr -d '[:space:]')"
    if [[ "$open" == "true" ]]; then
      cast send "$CONTRACT" "closeRound(uint256)" "$current" --rpc-url "$RPC_URL" --private-key "$KEY" >/dev/null
    fi
  fi
  sleep 5
done
