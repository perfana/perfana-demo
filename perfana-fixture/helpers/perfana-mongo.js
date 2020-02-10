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

const mc = require('./mongoDb')


module.exports.getGrafanaInstances = () => {

  return mc.get().db('perfana')
    .collection('grafanas')
    .find({})
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.upsertGrafanaInstance = (grafana) => {

  return mc.get().db('perfana')
    .collection('grafanas')
    .findOneAndUpdate({
      _id: grafana._id
    }, {
      $set: grafana
    }, {
      upsert: true,
      returnOriginal: false
    })
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.getGrafanaInstance = (id) => {

  return mc.get().db('perfana')
    .collection('grafanas')
    .findOne({
      _id: id
    })
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getGrafanaDashboardsForGrafanaInstance = (grafanaId) => {

  return mc.get().db('perfana')
    .collection('grafanaDashboards')
    .find({
      grafana: grafanaId
    })
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getSystemDashboardsByUid = (uid) => {

  return mc.get().db('perfana')
    .collection('systemDashboards')
    .find({
      dashboardUid: uid
    })
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getSystemDashboardsForSystemUnderTest = (system, testRun, grafanaDashboard) => {

  const dashboardUidRegex = new RegExp((system.name.toLowerCase().replace(/ /g, '-') + '-' + grafanaDashboard.name.toLowerCase().replace(/ /g, '-')).substring(0, 39), 'i')

  // console.log('dashboardUidRegex: ' + dashboardUidRegex)
  // console.log('grafanaDashboard.grafana: ' + grafanaDashboard.grafana)

  return mc.get().db('perfana')
    .collection('systemDashboards')
    .find({
      $and: [{
        grafana: grafanaDashboard.grafana
      },
      {
        dashboardUid: {
          $regex: dashboardUidRegex
        }
      },
      {
        system: testRun.system
      },
      {
        environment: testRun.environment
      }
      ]
    })
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getGrafanaDashboardByUid = (grafanaId, uid) => {

  return mc.get().db('perfana')
    .collection('grafanaDashboards')
    .findOne({
      $and: [{
        grafana: grafanaId
      },
      {
        uid: uid
      }
      ]
    })
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getSystem = (id) => {

  return mc.get().db('perfana')
    .collection('systems')
    .findOne({
        _id: id
    })
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getBenchmarksByUid = (uid) => {

  return mc.get().db('perfana')
    .collection('benchmarks')
    .find({
      dashboardUid: uid
    })
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}


module.exports.updateBenchmark = (benchmark) => {

  return mc.get().db('perfana')
    .collection('benchmarks')
    .updateOne({
      _id: benchmark._id
    }, {
      $set: benchmark
    })
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.upsertGrafanaDashboard = (grafanaDashboard) => {

  return mc.get().db('perfana')
    .collection('grafanaDashboards')
    .findOneAndUpdate({
      $and: [
        {
          grafana: grafanaDashboard.grafana
        },
        {
          uid: grafanaDashboard.uid
        },
      ]
    }, {
      $set: grafanaDashboard
    }, {
      upsert: true,
      returnOriginal: false
    })
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.updateSystemDashboard = (systemDashboard, grafanaDashboard) => {

  return mc.get().db('perfana')
    .collection('systemDashboards')
    .updateOne({
      _id: systemDashboard._id
    }, {
      $set: {
        dashboardName: grafanaDashboard.name
      }
    })
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertSystemDashboard = (systemDashboard) => {

  return mc.get().db('perfana')
    .collection('systemDashboards')
    .insertOne(
      systemDashboard
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.updateSystemDashboardVariables = (systemDashboard) => {

  return mc.get().db('perfana')
    .collection('systemDashboards')
    .findOneAndUpdate({
      $and: [
        {
          grafana: systemDashboard.grafana
        },
        {
          dashboardUid: systemDashboard.dashboardUid
        },
        {
          dashboardLabel: systemDashboard.dashboardlabel
        },
      ]
    }, {
      $set: {
        variables: systemDashboard.variables
      }
    })
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertGrafanaPerfanaSyncEvent = (grafanaInstance, grafanaDashboard, event, description, stackTrace) => {

  let eventObject = {
    timestamp: new Date(),
    event: event,
    grafana: grafanaInstance.label,
    name: grafanaDashboard.name,
    uid: grafanaDashboard.uid,
    message: description,
    stackTrace: stackTrace ? stackTrace : undefined,
  }

  return mc.get().db('perfana')
    .collection('GrafanaPerfanaSyncEvents')
    .insertOne(
      eventObject
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertAutoConfigGrafanaDashboard = (autoConfigGrafanaDashboard) => {

  return mc.get().db('perfana')
    .collection('autoconfigDashboards')
    .insertOne(
      autoConfigGrafanaDashboard
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertOrganisation = (organisation) => {

  return mc.get().db('perfana')
    .collection('organisations')
    .insertOne(
      organisation
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertUser = (user) => {

  return mc.get().db('perfana')
    .collection('users')
    .insertOne(
      user
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.insertTeam = (team) => {

  return mc.get().db('perfana')
    .collection('teams')
    .insertOne(
      team
    )
    .then(as => as)
    .catch(e => console.log(e))
}

module.exports.storeTemplatingValue = (grafana, dashboardUid, variableName, variableValue) => {

  return mc.get().db('perfana')
    .collection('grafanaDashboardsTemplatingValues')
    .updateOne({
      $and: [{
        grafana: grafana
      },
      {
        dashboardUid: dashboardUid
      },
      {
        variableName: variableName
      },
      {
        variableValue: variableValue
      },
      ]
    }, {
      $set: {
        updated: new Date()
      }
    }, {
      upsert: true
    })
    .then(as => as)
    .catch(e => console.log(e))

}
module.exports.getRecentTestRuns = (lastSyncTimestamp) => {

  return mc.get().db('perfana')
    .collection('testRuns')
    .find({
      end: {
        $gte: new Date(lastSyncTimestamp)
      }
    })
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}

module.exports.getAutoconfigDashboards = () => {

  return mc.get().db('perfana')
    .collection('autoconfigDashboards')
    .find({})
    .toArray()
    .then(as => as)
    .catch(e => console.log(e))

}
