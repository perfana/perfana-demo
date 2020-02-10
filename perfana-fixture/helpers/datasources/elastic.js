const yves = require('yves')
yves.debugger('Y', { stream: null, sortKeys: true, hideFunctions: true, singleLineMax: 0, obfuscates: [/key/i, /token/i] })
const config = require('config')
if (config.debug) {
  yves.debugger().enable(config.debug)
}

yves.debugger(config.debugPrefix)

