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
const {
  storeTemplatingValue
} = require('../perfana-mongo')
const {
  grafanaApiGet
} = require('../grafana-api')

yves.debugger(config.debugPrefix)

module.exports.getGraphiteVariables = (grafana, grafanaDashboard, datasource, variable, systemUnderTestQuery) => {

  return new Promise((resolve, reject) => {

    const queryUrl = '/api/datasources/proxy/' + datasource.id + '/metrics/find?query=' + systemUnderTestQuery;

    let variableValues = [];

    // console.log('queryUrl: ' + queryUrl)
    grafanaApiGet(grafana, queryUrl).then((variableValuesResponse) => {

      // console.log('graphite values response: ' + JSON.stringify(variableValuesResponse))
      if (variableValuesResponse) {
        variableValuesResponse.forEach((value) => {
          let variableValue = value.text;

          let valueAfterRegex = '';

          if (variable.regex && variable.regex !== '') {

            let valueRegex = new RegExp(variable.regex.slice(1, -1)); // remove '/' from start and end 

            let matches = variableValue.match(valueRegex);

            if (matches && variableValues.indexOf(variableValue) === -1) {

              variableValues.push(variableValue);

            }

          } else {

            if (variableValues.indexOf(variableValue) === -1) variableValues.push(variableValue);

          }

        })
      }

      // console.log('variableValues: ' + JSON.stringify(variableValues))

      resolve(variableValues);

    }).catch((err) => {
      console.log(`##### Error getting values for query "${queryUrl}" for variable "${variable.name}" in dashboard "${grafanaDashboard.name}" from grafana instance "${grafana.label}", ${err.stack}`)
      reject(err);
    })
  })
}