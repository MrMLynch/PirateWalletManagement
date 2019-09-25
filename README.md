# Pirate Wallet Management

## Script to reset pirate wallet.dat if it grows too big

### Expected behavior:
- For each address send funds to self and import keys in fresh wallet.dat from current blockheight - 100

### Error checks:
- daemon running
- config file present and live mode turned on
- cli and daemon executables present (must be amended to suit the environment)

### Features:
- takes backup of all privkeys in wallet.dat and stores them in the form `zsaddress : privkey` in file privkeys.txt -> !!! delete this after script runs successfully
- stores all opids from this procedure in the form `[RESULT]: zsaddress : balance -> opid` in file opids.txt -> retain this for future reference; !!! important for exchanges
- stores all txids from this procedure in the form `zsaddress - opid - txid` in file txids.txt -> retain this for future reference; !!! important for exchanges
- takes backup of old wallet.dat in the form of `wallet.bak.timestamp`
- checks for daemon restart
- checks balance at start and end of operation

### Edit config.json to suit your environment and set live to 1


#### Provided as is, no warranties given!
