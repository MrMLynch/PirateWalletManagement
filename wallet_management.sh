#!/bin/bash

# jq needs to be installed for this to work
# -----------------
# you MUST edit config.json and change "live" to 1 for this to work
# provided as is by mrlynch; please read before running
# DO NOT EDIT if you don't know what you're doing - you can mess up your wallet.dat
# Ask in discord if you have any questions: https://pirate.black/discord


cd "${BASH_SOURCE%/*}" || exit

RESET="\033[0m"
BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

timestamp() {
  date "+%Y/%m/%d-%H:%M:%S"
}

# check if config.json exists
if [ ! -f config.json ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: config.json not found in $(pwd)${RESET}"
  exit 0
fi

echo -e '\n Pirate wallet reset script v0.2b (c) '${MAGENTA}mrlynch${RESET}, 2019
echo    '===================================================='

# declare private keys array
privkeys=()

# check if config file has been edited

live=$(cat config.json | jq -r .live)
if [ "$live" -eq "0" ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: config.json has not been edited... This is critical!${RESET}"
  exit 0
fi

# getting required data from config.json
cli=$(cat config.json | jq -r .cli)
cli_daemon=$(cat config.json | jq -r .cli_daemon)
data_dir=$(cat config.json | jq -r .data_dir)

# check that cli and daemon files exist
if [ ! -f ${cli} ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: ${cli} not found!${RESET}"
  exit 0
fi

if [ ! -f ${cli_daemon} ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: ${cli_daemon} not found!${RESET}"
  exit 0
fi
echo -e "[$(timestamp)] - ${GREEN}Config data correct!${RESET}"

# check if daemon is running

if $(pgrep -af "komodod.*\-ac_name=PIRATE" > /dev/null); then
  echo -e "[$(timestamp)] - ${GREEN}Pirate daemon is running!${RESET}"
else
  echo -e "[$(timestamp)] ${RED}[ERROR]: Pirate daemon is not running. Start daemon and try again${RESET}\n"
  exit 0
fi

# get current blockheight and make sure chain is synced
current_blockheight=$(${cli} getinfo | jq -r .blocks)
longestchain=$(${cli} getinfo | jq -r .longestchain)

if [ "${current_blockheight}" != "${longestchain}" ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: chain is not in sync! Stopping!${RESET}"
  exit 0
else
  echo -e "[$(timestamp)] - ${GREEN}Chain is in sync!${RESET}"
  echo ""
fi
echo -e "[$(timestamp)] - ${GREEN}Proceeding...\n${RESET}"

# add timestamp to privkeys and opids files
echo -e "\nWallet Management Operation Private Keys at [$(timestamp)]\n" >> privkeys.txt
echo -e "\nWallet Management Operation Operation IDs at [$(timestamp)]\n" >> opids.txt
echo -e "\nWallet Management Operation Transaction IDs at [$(timestamp)]\n" >> txids.txt

# get blockchain height and oldest note -> for reference purposes
oldest_listunspent=$(${cli} z_listunspent | jq 'sort_by(.rawconfirmations)[-1].rawconfirmations')
echo -e "[$(timestamp)] - Oldest note is ${oldest_listunspent} blocks\n"

# we deduct a further 100 blocks for good measure
rescan_height=$((${current_blockheight}-100))
addresses=$(${cli} z_listaddresses | jq .[] -r)

echo -e "[$(timestamp)] - Shielded balance at start of operation: ${GREEN}$(${cli} z_gettotalbalance | jq -r '.private')${RESET}"

echo "[$(timestamp)] - Extracting private keys..."
for address in $addresses
do
    # export all private keys and resend funds
    echo -e "[$(timestamp)] - Address: ${YELLOW}${address}${RESET}"
    privkey=$(${cli} z_exportkey ${address})
    echo -e "[$(timestamp)] - Private key: ${CYAN}${privkey}${RESET}"
    echo "[$(timestamp)] - Adding to array and exporting to file..."
    echo "-------------------------------"
    privkeys+=(${privkey})
    echo "${address} : ${privkey}" >> privkeys.txt

    # checking for balance greater than 0 and send funds to self
    balance=$(${cli} z_getbalance ${address})
    if (( $(bc <<< "$balance > 0") )); then
        opid=$(${cli} z_sendmany ${address} "[{\"address\":\"${address}\", \"amount\":$(bc -l <<< ${balance}-0.0001 | sed 's/^\./0./')}]")
        echo -e "[$(timestamp)] - Self send operation of ${GREEN}${balance}${RESET} from ${YELLOW}${address}${RESET} successful... Saving opid ${GREEN}${opid}${RESET} to file..."

        echo "[$(timestamp)] - Checking opid status..."
        while [ $(${cli} z_getoperationstatus "[\"${opid}\"]" | jq .[].status -r) == "executing" ]; do
            printf "."
            sleep 1
        done
        echo ""

        if [ $(${cli} z_getoperationstatus "[\"${opid}\"]" | jq .[].status -r) == "success" ]
        then
            echo "[SUCCESS]: ${address} : ${balance} -> ${opid}" >> opids.txt
            txid=$(${cli} z_getoperationstatus "[\"${opid}\"]" | jq .[].result.txid -r)
            echo -e "[$(timestamp)] ${GREEN}[SUCCESS]${RESET}: Opid: ${GREEN}${opid}${RESET}"
            echo -e "[$(timestamp)] ${GREEN}[SUCCESS]${RESET}: Txid: ${GREEN}${txid}${RESET}"
            echo -e "[$(timestamp)] - Saving txid to file..."
            echo -e "${address} - ${opid} - ${txid}" >> txids.txt
            echo "-------------------------------"
        else
            echo "[ERROR]: ${address} : ${balance} -> ${opid}" >> opids.txt
            echo -e "[$(timestamp)] ${RED}[ERROR]${RESET}: opid ${RED}${opid}${RESET} status returned other than success, stopping operation for manual investigation..."
            echo "-------------------------------"
            exit 0
        fi
    else
        echo -e "[$(timestamp)] - ${YELLOW}${address}${RESET} has ${RED}0 ARRR${RESET} balance... skipping; privkey still stored..."
        echo "-------------------------------"
    fi
done

echo -e "[$(timestamp)] - Sleep for 60s"
sleep 60
# gracefully shutting down the daemon
echo -e "[$(timestamp)] - ${RED}Stopping daemon...${RESET}"
${cli} stop
sleep 30

echo -e "[$(timestamp)] - Backing up old wallet.dat and creating new one..."
# create new wallet.dat and backup old one with timestamp
backupwallet="wallet.bak.$(date "+%Y%m%d-%H%M%S")"
mv "${data_dir}/wallet.dat" "${data_dir}/${backupwallet}"
if [ ! -f "${data_dir}/${backupwallet}" ]; then
  echo -e "[$(timestamp)] ${RED}[ERROR]: Backup ${backupwallet} not created. Stopping operation for manual investigation!${RESET}"
  exit 0
else
  echo -e "[$(timestamp)] ${GREEN}[SUCCESS]: Backup ${backupwallet} created!${RESET}"
fi

sleep 5

echo -e "[$(timestamp)] - Restarting daemon! Please wait..."
${cli_daemon} > /dev/null 2>&1 &

count=0
while [ "${count}" -le "120" ]; do
  printf "${GREEN}.${RESET}"
  ((++count))
  sleep 1
done
echo -e ""

# check if daemon restarted successfully

if $(pgrep -af "komodod.*\-ac_name=PIRATE" > /dev/null); then
  echo -e "[$(timestamp)] ${GREEN}[SUCCESS]${RESET}: Pirate daemon started successfully!"
else
  echo -e "[$(timestamp)] ${RED}[ERROR]${RESET}: Pirate daemon didn't restart. Help human - check debug.log in data_dir..."
  exit 0
fi

echo -e "[$(timestamp)] - Reimporting private keys..."
# reimport private keys from target blockheight

# check if privkey array contains more than 1 key
if [ "${#privkeys[@]}" -ge "2" ]; then
  for privkey in "${privkeys[@]:1}"
  do
    $(${cli} z_importkey ${privkey} no)
  done
  $(${cli} z_importkey ${privkeys[0]} yes ${rescan_height})
else
  $(${cli} z_importkey ${privkeys[0]} yes ${rescan_height})
fi

echo -e "[$(timestamp)] ${GREEN}[SUCCESS]${RESET}: Wallet reset complete"
echo -e "[$(timestamp)] - Old wallet size - $(ls -lh ${data_dir}/${backupwallet} | awk '{print $5}')"
echo -e "[$(timestamp)] - New wallet size - $(ls -lh ${data_dir}/wallet.dat | awk '{print $5}')"
echo -e "[$(timestamp)] - Shielded balance at end of operation: ${GREEN}$(${cli} z_gettotalbalance | jq -r '.private')${RESET}"
