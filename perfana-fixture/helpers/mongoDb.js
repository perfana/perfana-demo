const yves = require('yves')
yves.debugger('Y', { stream: null, sortKeys: true, hideFunctions: true, singleLineMax: 0, obfuscates: [/key/i, /token/i] })
const config = require('config')
if (config.debug) {
  yves.debugger().enable(config.debug)
}

yves.debugger(config.debugPrefix)

const MongoClient = require("mongodb").MongoClient;

const options = {
  useNewUrlParser: true,
  reconnectInterval: 10000, // wait for 10 seconds before retry
  reconnectTries: Number.MAX_VALUE, // retry forever
};

const url = process.env.MONGO_URL

let connection = null;

module.exports.connect = () => new Promise((resolve, reject) => {
  MongoClient.connect(url, options, function(err, mc) {
    if (err) { reject(err); return; };
    resolve(mc);
    connection = mc;
  });
});

module.exports.get = () => {
  if(!connection) {
    throw new Error('Call connect first!');
  }

  return connection;
}