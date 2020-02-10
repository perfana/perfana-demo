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

module.exports.getInfluxVariables = (grafana, grafanaDashboard, datasource, variable, systemUnderTestQuery) => {

  return new Promise((resolve, reject) => {

    const queryUrl = '/api/datasources/proxy/' + datasource.id + '/query?db=' + datasource.database + '&q=' + systemUnderTestQuery;

    let variableValues = [];

    grafanaApiGet(grafana, queryUrl).then((variableValuesResponse) => {

      if (variableValuesResponse.results) {
        variableValuesResponse.results.forEach((result) => {

          if (result.series) {
            result.series.forEach((serie) => {

              if (serie.values) {
                serie.values.forEach((value) => {

                  let variableValue = value.length === 1 ? value[0] : value[1]; // if query == 'show measurements' values come in array of single strings

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
            })
          }
        })
      }

      resolve(variableValues);

    }).catch((err) => { 
      console.log(`##### Error getting values for query "${queryUrl}" for variable "${variable.name}" in dashboard "${grafanaDashboard.name}" from grafana instance "${grafana.label}", ${err.stack}`)
      reject(err);
    })
  })
}