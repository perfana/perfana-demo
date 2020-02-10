const { grafanaApiPost, grafanaApiGet } = require('../helpers/grafana-api')

const {
  getGrafanaInstances,
  upsertGrafanaInstance,
  insertAutoConfigGrafanaDashboard,
  insertOrganisation,
  insertTeam,
  insertUser,
} = require('../helpers/perfana-mongo')

const Random = require('meteor-random')

const fs = require('fs')

var path = require('path')

const Promise = require('bluebird')



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

module.exports = () => {

    
    getGrafanaInstances().then((grafanaInstances) => { // Get all configured Grafana instances

      if (grafanaInstances.length === 0) {

        addGrafanaInstance().then((createdGrafanaDocument) => {
              
          // upload grafana datasource and dashboards
          postGrafanaResources(createdGrafanaDocument)

                // store preconfigured users
                fs.readdir(path.resolve(__dirname,'./users'), (err, files) => {

            console.log('Inserting users')

                  files.forEach((file) => {

              insertUser(JSON.parse(fs.readFileSync(path.resolve(__dirname, './users') + '/' + file)))

            })

          })
          // store preconfigured organisations
          fs.readdir(path.resolve(__dirname,'./organisations'), (err, files) => {

            console.log('Inserting organisations')
                  
                  files.forEach((file) => {

              insertOrganisation(JSON.parse(fs.readFileSync(path.resolve(__dirname, './organisations') + '/' + file)))

            })

          })
          // store preconfigured teams
          fs.readdir(path.resolve(__dirname,'./teams'), (err, files) => {

            console.log('Inserting teams')
                  
                  files.forEach((file) => {

              insertTeam(JSON.parse(fs.readFileSync(path.resolve(__dirname, './teams') + '/' + file)))

            })

          })
          // store preconfigured autoconfig dashboards
          fs.readdir(path.resolve(__dirname,'./autoConfigGrafanaDashboards'), (err, files) => {

            console.log('Inserting autoconfig dashboards')
                  
                  files.forEach((file) => {

              insertAutoConfigGrafanaDashboard(JSON.parse(fs.readFileSync(path.resolve(__dirname, './autoConfigGrafanaDashboards') + '/' + file)))

            })

          })

        
        }).catch((err) => {
                  
          console.log(err)

        })
      }
    })    

}

const addGrafanaInstance = () => {
    
  return new Promise((resolve, reject) => {
        

    let grafana = {
      _id: 'demo',
      label: 'Demo',
      clientUrl: 'http://localhost:3000',
      serverUrl: 'http://localhost:3000',
      orgId: '1',
      username: 'perfana',
      password: 'perfana',
      snapshotInstance: true,
      trendsInstance: true
    }

    upsertGrafanaInstance(grafana).then((storedGrafana) => {
          
      // create API key

      const apiKey = {
        name: 'Perfana',
        role: 'Admin'
      }

      grafanaApiPost(storedGrafana.value, '/api/auth/keys', apiKey).then((response) => {
              
        storedGrafana.value.apiKey = response.key

                upsertGrafanaInstance(storedGrafana.value).then((updatedGrafana) => {

          resolve(updatedGrafana.value)

                })    


      })
    })


  })
}

const postGrafanaResources = (grafanaDocument) => {

  // create folder
           
  let folder = {
    uid: 'templates-folder',
    title: 'Templates'
  }

  grafanaApiPost(grafanaDocument, '/api/folders', folder).then((response) => {

    // create datasources

    fs.readdir(path.resolve(__dirname, './grafana/datasources'), (err, files) => {

      Promise.each(files, (file) => {

        return grafanaApiPost(grafanaDocument, '/api/datasources', JSON.parse(fs.readFileSync(path.resolve(__dirname, './grafana/datasources/') + '/' + file)))


      }).then((result) => {

        console.log('Uploaded datasources from fixture data ...')

          }).catch((err) => {

        console.log(err)

          })
          // files.forEach(file => {
          //
          //       grafanaApiPost(grafanaDocument, '/api/datasources', JSON.parse(fs.readFileSync(path.resolve(__dirname, './grafana/datasources/') + '/' + file)))
          //
          //   });
        })

        // create dashboards

        fs.readdir(path.resolve(__dirname,'./grafana/dashboards'), (err, files) => {
      Promise.each(files, (file) => {

        return grafanaApiPost(grafanaDocument, '/api/dashboards/db', JSON.parse(fs.readFileSync(path.resolve(__dirname,'./grafana/dashboards/') + '/' + file)))

      }).then((result) => {

        console.log('Uploaded dashboards from fixture data ...')

          }).catch((err) => {

        console.log(err)

          })
          // files.forEach(file => {
          //
          //       grafanaApiPost(grafanaDocument, '/api/dashboards/db', JSON.parse(fs.readFileSync(path.resolve(__dirname,'./grafana/dashboards/') + '/' + file)))
          //
          //   });
        })

      })

    
}