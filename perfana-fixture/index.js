
const fixture = require("./fixture/fixture")

const yves = require('yves')

yves.debugger('Y', {
  stream: null,
  sortKeys: true,
  hideFunctions: true,
  singleLineMax: 0,
  obfuscates: [/key/i, /token/i]
})

const config = require('config')


if (config.debug) {
  yves.debugger().enable(config.debug)
}

yves.debugger(config.debugPrefix)

process.on('unhandledRejection', (reason, promise) => {
  console.log('Unhandled Rejection at:', reason.stack || reason)
})

// debug('Configuration for [%s] %Y', config.env, config.util.toObject(config))

const db = require('./helpers/mongoDb');


  setTimeout(() => {
    db.connect()
    .then(() => console.log('database connected'))
    .then(() => fixture())
    .catch((e) => {
      console.error(e);
      // Always hard exit on a database connection error
      process.exit(1);
    });

  }, 20 * 1000) // allow containers to start up 
  
  
