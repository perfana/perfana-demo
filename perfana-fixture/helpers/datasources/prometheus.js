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
const _ = require('lodash')
const {
  JSONPath
} = require('jsonpath-plus');


yves.debugger(config.debugPrefix)

module.exports.getPrometheusVariables = (grafana, grafanaDashboard, datasource, variable, systemUnderTestQuery) => {

  return new Promise((resolve, reject) => {

    let queryUrl;

    const queryRegex =new RegExp('label_values\\((.*),\\s*([^\)]+)\\)');

    if (queryRegex.test(systemUnderTestQuery)) {

      let metric = queryRegex.exec(systemUnderTestQuery)[1];

      queryUrl = '/api/datasources/proxy/' + datasource.id + '/api/v1/series?match[]=' + metric + '&start=' + Math.round(new Date(new Date().setDate(new Date().getDate() - 1)).getTime() / 1000) + '&end=' + Math.round(new Date().getTime() / 1000);

    } else {

      queryUrl = '/api/datasources/proxy/' + datasource.id + '/api/v1/label/' + variable.name + '/values';

    }

    let variableValues = [];

    grafanaApiGet(grafana, queryUrl).then((variableValuesResponse) => {

      if (queryRegex.test(systemUnderTestQuery)) {

        let property = queryRegex.exec(systemUnderTestQuery)[2];

        // console.log(JSON.stringify(valuesResponse))
        _.each(_.uniq(JSONPath({
          json: variableValuesResponse,
          path: '$.data[*].' + property
        })), variableValue => {

          let valueAfterRegex = '';

          if (variable.regex && variable.regex !== '') {

            let valueRegex = new RegExp(variable.regex.slice(1, -1));
            let matches = variableValue.match(valueRegex);

            _.each(matches, (match, i) => {

              if (i > 0) valueAfterRegex += match;

            })

          }

          let pushValue = (valueAfterRegex !== '') ? valueAfterRegex : variableValue;
          if (variableValues.indexOf(pushValue) === -1) variableValues.push(pushValue)

        });

      } else {

        _.each(variableValuesResponse.data, variableValue => {

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

      resolve(variableValues);
      
    }).catch((err) => { 
      console.log(`##### Error getting values for query "${queryUrl}" for variable "${variable.name}" in dashboard "${grafanaDashboard.name}" from grafana instance "${grafana.label}", ${err.stack}`)
      reject(err);
    })
  })
}