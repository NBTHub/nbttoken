'use strict';
const constants = require('byteballcore/constants.js');
const conf = require('byteballcore/conf');
const localConf = require('./conf.json'); // *
const db = require('byteballcore/db');
const eventBus = require('byteballcore/event_bus');
const texts = require('./texts');
const wallet = require('byteballcore/wallet.js');
const validationUtils = require('byteballcore/validation_utils');
const notifications = require('./modules/notifications');
const byteball_ins = require('./modules/byteball_ins');
const conversion = require('./modules/conversion-and-headless.js');
const desktopApp = require('byteballcore/desktop_app.js');
const pool = require('./modules/mysql_connect.js'); // *
var connection = pool();
const headlessWallet = require('./start_headless.js');

var CURRENT_TIMESTAMP = { toSqlString: function() { return 'CURRENT_TIMESTAMP()'; } }; // *

if (!localConf.created_asset) {
    throw Error("config asset");
}

conversion.enableRateUpdates();

function sendTokensToUser(objPayment) {
	const mutex = require('byteballcore/mutex');
	mutex.lock(['tx-' + objPayment.transaction_id], unlock => {
		db.query("SELECT paid_out FROM transactions WHERE transaction_id=?", [objPayment.transaction_id], rows => {
			if (rows.length === 0)
				throw Error('tx ' + objPayment.transaction_id + ' not found');
			if (rows[0].paid_out)
				return unlock();
			headlessWallet.issueChangeAddressAndSendPayment(
                localConf.created_asset, objPayment.tokens, objPayment.byteball_address, objPayment.device_address,
				(err, unit) => {
					if (err) {
						notifications.notifyAdmin('sendTokensToUser ICO failed', err + "\n\n" + JSON.stringify(objPayment, null, '\t'));
						return unlock();
					}
					db.query(
						"UPDATE transactions SET paid_out = 1, paid_date = " + db.getNow() + ", payout_unit=? WHERE transaction_id = ? AND paid_out = 0",
						[unit, objPayment.transaction_id],
						() => {
							unlock();
                            connection.query('SELECT sale_id FROM sale WHERE platform = ? AND tx_id=?', ['byteball', objPayment.transaction_id], function(err, rows) { // *
                                if (!err && rows.length > 0) {

                                } else {
                                	let currency_amount = parseInt(typeof objPayment.currency_amount != 'undefined' ? objPayment.currency_amount * 10**9 : 0);
                                    connection.query(
                                        "INSERT IGNORE INTO sale (platform, input, bonus, tx_id, unit, address, total_tokens, status, status_at, created_at, updated_at) VALUES ('byteball', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                        [currency_amount, conf.BONUS, objPayment.transaction_id, unit, objPayment.byteball_address, objPayment.tokens, 'sended', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP],
                                        (err) => {
                                            console.error('db err', err);
                                        }
                                    );
                                }
                            });
						}
					);
				}
			);
		});
	});
}

eventBus.on('paired', from_address => {
	let device = require('byteballcore/device.js');
	var text = texts.greeting();
	checkUserAdress(from_address, 'BYTEBALL', bByteballAddressKnown => {
		if (bByteballAddressKnown)
			text += "\n\n" + texts.howmany();
		else
			text += "\n\n" + texts.insertMyAddress();
		device.sendMessageToDevice(from_address, 'text', text);
	});
});

eventBus.once('headless_and_rates_ready', () => {
    const headlessWallet = require('./start_headless.js');
	headlessWallet.setupChatEventHandlers();
	eventBus.on('text', (from_address, text) => {
		let device = require('byteballcore/device');
		text = text.trim();
		let ucText = text.toUpperCase();
		let lcText = text.toLowerCase();

		let arrProfileMatches = text.match(/\(profile:(.+?)\)/);
		
		checkUserAdress(from_address, 'BYTEBALL', bByteballAddressKnown => {
			if (!bByteballAddressKnown && !validationUtils.isValidAddress(ucText) && !arrProfileMatches)
				return device.sendMessageToDevice(from_address, 'text', texts.insertMyAddress());
			
			function handleUserAddress(address, bWithData){
				function saveByteballAddress(){
					db.query(
						'INSERT OR REPLACE INTO user_addresses (device_address, platform, address) VALUES(?,?,?)', 
						[from_address, 'BYTEBALL', address], 
						() => {
							device.sendMessageToDevice(from_address, 'text', 'Saved your Byteball address'+(bWithData ? ' and personal data' : '')+'.\n\n' + texts.howmany());
						}
					);
				}
                return saveByteballAddress();
			}
			
			if (validationUtils.isValidAddress(ucText)) {
				if (conf.bRequireRealName)
					return device.sendMessageToDevice(from_address, 'text', "You have to provide your attested profile, just Byteball address is not enough.");
				return handleUserAddress(ucText);
			}
			else if (arrProfileMatches){
                return device.sendMessageToDevice(from_address, 'text', "Private profile is not required");
			} else if (/^[0-9.]+[\sA-Z]+$/.test(ucText)) {
				let amount = parseFloat(ucText.match(/^([0-9.]+)[\sA-Z]+$/)[1]);
				let currency = ucText.match(/[A-Z]+$/)[0];
				if (amount < 0.000000001)
					return device.sendMessageToDevice(from_address, 'text', 'Min amount 0.000000001');
				let tokens, display_tokens;
				switch (currency) {
					case 'GB':
					case 'GBYTE':
						let bytes = Math.round(amount * 1e9);
						tokens = conversion.convertCurrencyToTokens(amount, 'GBYTE');
                        tokens = Math.floor(tokens);
						if (tokens === 0)
							return device.sendMessageToDevice(from_address, 'text', 'The amount is too small');

                        if (Math.floor(tokens / 10**conf.tokenDisplayDecimals) < conf.MIN_TOKENS) {
                            return device.sendMessageToDevice(from_address, 'text', 'You are going to purchase ' + (tokens / conversion.displayTokensMultiplier) + ' ' + conf.tokenName + '.  \nMinimum purchase amount - ' + conf.MIN_TOKENS + ' ' + conf.tokenName);
						}

                        if (conf.BONUS > 0 && (conf.MAX_SALEABLE_TOKENS - total <= conf.BONUS_LIMIT)) {
                            tokens += tokens * conf.BONUS / 100;
                        }
                        tokens = Math.floor(tokens);


                        db.query(
                            "SELECT SUM(amount) AS total_left FROM my_addresses CROSS JOIN outputs USING(address) WHERE is_spent=0 AND asset = ? AND EXISTS (SELECT 1 FROM inputs CROSS JOIN my_addresses USING(address) WHERE inputs.unit=outputs.unit AND inputs.asset=?)",
                            [localConf.created_asset, localConf.created_asset],
                            rows => {
                                let total_left = rows[0].total_left;
                                if (total_left < tokens && !conf.bLight) {
                                    device.sendMessageToDevice(from_address, 'text', 'The amount is too large, total tokens left: ' + total_left);
								} else {
                                    display_tokens = tokens / conversion.displayTokensMultiplier;
                                    console.error('display_tokens', display_tokens);
                                    byteball_ins.readOrAssignReceivingAddress(from_address, receiving_address => {
                                        device.sendMessageToDevice(from_address, 'text', 'You buy: ' + display_tokens + ' ' + conf.tokenName + '\n including stage\'s bonus - ' + conf.BONUS + '%' +
                                            '\n[' + ucText + '](byteball:' + receiving_address + '?amount=' + bytes + ')');
                                    });
								}
                            }
                        );
						break;
					default:
						device.sendMessageToDevice(from_address, 'text', 'Currency is not supported');
						break;
				}
				return;
			}

			let response = texts.greeting();
			if (bByteballAddressKnown)
				response += "\n\n" + texts.howmany();
			else
				response += "\n\n" + texts.insertMyAddress();
			device.sendMessageToDevice(from_address, 'text', response);
		});
	});
});

function checkAndPayNotPaidTransactions() {
	let network = require('byteballcore/network.js');
	if (network.isCatchingUp())
		return;
	console.log('checkAndPayNotPaidTransactions');
	db.query(
		"SELECT transactions.* \n\
		FROM transactions \n\
		LEFT JOIN outputs ON byteball_address=outputs.address AND tokens=outputs.amount AND asset=? \n\
		LEFT JOIN unit_authors USING(unit) \n\
		LEFT JOIN my_addresses ON unit_authors.address=my_addresses.address \n\
		WHERE my_addresses.address IS NULL AND paid_out=0 AND stable=1",
		[localConf.created_asset],
		rows => {
			rows.forEach(sendTokensToUser);
		}
	);
}


function checkUserAdress(device_address, platform, cb) {
	db.query("SELECT address FROM user_addresses WHERE device_address = ? AND platform = ?", [device_address, platform.toUpperCase()], rows => {
		if (rows.length) {
			cb(true)
		} else {
			cb(false)
		}
	});
}


function getPlatformByCurrency(currency) {
	switch (currency) {
		case 'GBYTE':
			return 'BYTEBALL';
		default:
			throw Error("unknown currency: " + currency);
	}
}

eventBus.on('in_transaction_stable', tx => {
	let device = require('byteballcore/device');
	const mutex = require('byteballcore/mutex');
	mutex.lock(['tx-' + tx.txid], unlock => {
		db.query("SELECT stable FROM transactions WHERE txid = ? AND receiving_address=?", [tx.txid, tx.receiving_address], rows => {
			if (rows.length > 1)
				throw Error("non unique");
			if (rows.length && rows[0].stable) return;

			if (conf.rulesOfDistributionOfTokens === 'one-time' && conf.exchangeRateDate === 'distribution') {
				db.query(
					"INSERT INTO transactions (txid, receiving_address, currency, byteball_address, device_address, currency_amount, tokens, stable) \n\
					VALUES(?, ?,?, ?,?,?,?, 1)",
					[tx.txid, tx.receiving_address, tx.currency, tx.byteball_address, tx.device_address, tx.currency_amount, null],
					() => {
						unlock();
						if (tx.device_address)
							device.sendMessageToDevice(tx.device_address, 'text', texts.paymentConfirmed());
					}
				);
			}
			else {
				let tokens = conversion.convertCurrencyToTokens(tx.currency_amount, tx.currency);
                tokens = Math.floor(tokens);
                console.error(tokens)
				if (tokens === 0) {
					unlock();
					if (tx.device_address)
						device.sendMessageToDevice(tx.device_address, 'text', "The amount is too small to issue even 1 token, payment ignored");
					return;
				}

                headlessWallet.readSingleWallet(function (wallet_id) {
                    wallet.readBalance(wallet_id, function(assocBalances){
                        var total = 0;
                        for (var asset in assocBalances){
                            if (asset === localConf.created_asset) {
                                var total = assocBalances[asset].stable + assocBalances[asset].pending;
                            }
                        }
                        if (conf.BONUS > 0 && (conf.MAX_SALEABLE_TOKENS - total <= conf.BONUS_LIMIT) ) {
                            tokens += tokens * conf.BONUS / 100;
                        }
                        tokens = Math.floor(tokens);
                        db.query(
                            "INSERT INTO transactions (txid, receiving_address, currency, byteball_address, device_address, currency_amount, tokens, stable) \n\
					VALUES(?, ?,?, ?,?,?,?, 1)",
                            [tx.txid, tx.receiving_address, tx.currency, tx.byteball_address, tx.device_address, tx.currency_amount, tokens],
                            (res) => {
                                unlock();
                                tx.transaction_id = res.insertId;
                                tx.tokens = tokens;
                                if (conf.rulesOfDistributionOfTokens === 'real-time')
                                    sendTokensToUser(tx);
                                else if (tx.device_address)
                                    device.sendMessageToDevice(tx.device_address, 'text', texts.paymentConfirmed());
                            }
                        );
                    });
				});
			}
		});
	});
});

eventBus.on('new_in_transaction', tx => {
	let device = require('byteballcore/device.js');
    device.sendMessageToDevice(tx.device_address, 'text', "Received your payment of " + tx.currency_amount + " " + tx.currency + ", waiting for confirmation.");
});

eventBus.on('headless_wallet_ready', () => {
	if (conf.rulesOfDistributionOfTokens === 'real-time') {
		setInterval(checkAndPayNotPaidTransactions, 3600 * 1000);
	}
});

function onError(err) {
	console.error('onError', err);
}