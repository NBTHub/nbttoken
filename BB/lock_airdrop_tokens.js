'use strict';
const fs = require('fs');
const headlessWallet = require('./start_readpass.js');
const conf = require('byteballcore/conf');
const eventBus = require('byteballcore/event_bus.js');
const db = require('byteballcore/db');
const constants = require('byteballcore/constants');
const desktopApp = require('byteballcore/desktop_app.js');
const device = require('byteballcore/device.js');
const objectHash = require('byteballcore/object_hash.js');
const async = require("async");

const localConfFile = './conf.json';
const localConf = require(localConfFile);

const MIN_BALANCE = 10000; // bytes
const TOTAL_TOKENS = 10000000000 * 10**5; // 10 billions of NBT
const TOTAL_AIRDROP_TOKENS = 8000000000 * 10**5; // 8 billions of NBT
const MAX_AIRDROP_VOLUME = 2; // %
const TIMESTAMPER_ADDRESS = 'I2ADHGP4HL6J37NQAD73J7E5SKFIXJOT';
const AIRDROP_WALLET_ADDRESS = "";
const AIRDROP_DEVICE_ADDRESS = "";
const FIRST_AIRDROP_TIMESTAMP = 1525122000 * 1000; // ms
const AIRDROP_PERIOD = 86400 * 1000; // ms
const FALLBACK_UNLOCK_TIMESTAMP = FIRST_AIRDROP_TIMESTAMP + 100 * 86400 * 1000; // after 100 days from first airdrop

headlessWallet.setupChatEventHandlers();

function onError(err) {
    console.error(err);
    throw Error(err);
}

let myAddress = null;

function lockTokens() {
    var walletDefinedByAddresses = require('byteballcore/wallet_defined_by_addresses.js');
    if (!localConf.created_asset) {
        return false;
    }

    db.query(
        "SELECT address, SUM(amount) AS amount FROM my_addresses CROSS JOIN outputs USING(address) JOIN units USING(unit) \n\
        WHERE is_spent=0 AND asset IS NULL AND is_stable=1 GROUP BY address",
        rows => {
            for (let i = 0;
                 i < rows.length;
                 i++
            ) {
                if (rows[i].amount >= MIN_BALANCE) {
                    myAddress = rows[i].address;
                    break;
                }
            }
            if (myAddress === null) {
                return db.query("SELECT address FROM my_addresses LIMIT 1", rows => {
                    console.error("==== Please refill your balance to pay for the fees, your address is " + rows[0].address + ", minimum balance is " + MIN_BALANCE + " bytes.");
                });
            }

            var arrOutputs = [];

            let onHandTokens = TOTAL_TOKENS - TOTAL_AIRDROP_TOKENS;
            let notDistributedTokens = TOTAL_AIRDROP_TOKENS;

            let i = 0;
            async.whilst(
                function() { return notDistributedTokens > 0 && i < constants.MAX_OUTPUTS_PER_PAYMENT_MESSAGE },

                function(callback) {
                    let unlock_at = FIRST_AIRDROP_TIMESTAMP + i * AIRDROP_PERIOD;
                    let amount = Math.floor(onHandTokens * MAX_AIRDROP_VOLUME / 100);
                    if (amount > notDistributedTokens) {
                        amount = notDistributedTokens;
                    }

                    let arrDefinition = ['or', [
                        ['and', [
                            ['address', AIRDROP_WALLET_ADDRESS],
                            ['in data feed', [[TIMESTAMPER_ADDRESS], 'timestamp', '>', unlock_at]]
                        ]],
                        ['and', [
                            ['address', myAddress],
                            ['in data feed', [[TIMESTAMPER_ADDRESS], 'timestamp', '>', FALLBACK_UNLOCK_TIMESTAMP]]
                        ]]
                    ]];

                    let signers = {
                        'r.0.0': {
                            address: AIRDROP_WALLET_ADDRESS,
                            member_signing_path: 'r',
                            device_address: AIRDROP_DEVICE_ADDRESS
                        },
                        'r.1.0': {
                            address: myAddress,
                            member_signing_path: 'r',
                            device_address: device.getMyDeviceAddress()
                        }
                    };

                    let shared_address = objectHash.getChash160(arrDefinition);


                    db.query("SELECT 1 FROM shared_addresses WHERE shared_address=?", [shared_address], function(rows){
                        if (rows.length > 0) {
                            console.error("Address already used, please try again");
                            return false;
                        }

                        walletDefinedByAddresses.createNewSharedAddress(arrDefinition, signers, {
                            ifOk: function(shared_address){

                                arrOutputs.push({amount: amount, address: shared_address});

                                onHandTokens += amount;
                                notDistributedTokens -= amount;
                                i++;
                                callback(null);
                            },
                            ifError: function(err){
                                callback(err);
                            }
                        });
                    });
                },

                function() {
                    headlessWallet.sendPaymentUsingOutputs(localConf.created_asset, arrOutputs, myAddress, (err, unit) => {
                        if (err) {
                            return onError(err)
                        }

                        eventBus.once('my_stable-' + unit, () => {
                            console.log('end');
                        });
                    });
                }
            );

        });
}

eventBus.on('headless_wallet_ready', lockTokens);
