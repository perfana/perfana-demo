  const yves = require('yves')
yves.debugger('Y', { stream: null, sortKeys: true, hideFunctions: true, singleLineMax: 0, obfuscates: [/key/i, /token/i] })
const config = require('config')
if (config.debug) {
  yves.debugger().enable(config.debug)
}

yves.debugger(config.debugPrefix)

const rp = require('request-promise-native');


module.exports.grafanaApiGet = (grafana, endpoint) => {

  const token = grafana.apiKey && grafana.apiKey !== '' ? 'Bearer ' + grafana.apiKey : undefined;

  const auth = {
    user: grafana.username,
    pass: grafana.password,
    sendImmediately: false
  };

  const apiUrl = grafana.serverUrl ? grafana.serverUrl + endpoint : grafana.clientUrl + endpoint;

  const options = {
    uri: apiUrl,
    json: true,
  };

  if (token) {

    options['headers'] = {
      'Authorization': token,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };

  } else {

    options['headers'] = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    options['auth'] = auth;

  }

  return rp(options).catch((err) => {
    const message = `Call to Grafana instance ${grafana.label}, endpoint ${apiUrl} failed, error: ${err}`;
    throw new Error(message);
  });

}

module.exports.grafanaApiPost = (grafana, endpoint, postData) => {


  const token = grafana.apiKey && grafana.apiKey !== '' ? 'Bearer ' + grafana.apiKey : undefined;

  const auth = {
    user: grafana.username,
    pass: grafana.password,
    sendImmediately: true
  };

  const apiUrl = grafana.serverUrl ? grafana.serverUrl + endpoint : grafana.clientUrl + endpoint;

  const options = {
    method: 'POST',
    uri: apiUrl,
    json: true,
    body: postData,
  };

  if (token) {

    options['headers'] = {
      'Authorization': token,
    };

  } else {

    options['auth'] = auth;

  }

  return rp(options).catch((err) => {
    const message = `Call to Grafana instance ${grafana.label}, endpoint ${apiUrl} failed, error: ${err}`;
    throw new Error(message);
  });

}

