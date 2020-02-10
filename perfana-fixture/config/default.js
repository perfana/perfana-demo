const debugPrefix = 'perfana'
module.exports = {
  debugPrefix,
  debug: process.env.hasOwnProperty('DEBUG') ? process.env.DEBUG : `${debugPrefix}*`,
  env: process.env.NODE_ENV || 'default',
  grafana: {
    token: '',
  },
  sync: {
    interval: 30 * 1000, // 1 minute
  },
}
