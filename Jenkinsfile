// Jenkinsfile used for habbuild process to update Habitat packages when new versions of upstream aig_compliance cookbook are built
library 'aigKitchen'
// Begin Declarative Pipeline configuration
pipeline {
  agent any
  parameters {
    string(defaultValue: '', description: '', name: 'pkgversion')
    string(defaultValue: 'false', description: '', name: 'autobuild')
  }
  stages {
    stage('checkout') {
      steps {
        sh 'git log -n1'
        script {
          if (env.BRANCH_NAME == 'master') {
            if (params.autobuild == 'true') {
              echo 'Building from master with autobuild options'
              echo "Using autobuild: ${params.autobuild} and pkgversion: ${params.pkgversion} recieved from upstream job request."
            }
            else {
              echo 'Building from current master without autobuild customizations'
              def jsonData = readJSON file: "${env.WORKSPACE}/pipeline.json"
              def version_draft = jsonData.version
              def version_check = sh returnStdout: true, script: "curl -f -s ${jsonData.publish_location}/${version_draft} | jq -r .total_count"
              echo "version_draft is $version_draft"
              echo "version_check status is $version_check"
              echo "pkgversion is $pkgversion"
              if (version_check.toInteger() > 0) {
                throw new Exception("Checkout version ${version_draft} already exists!!  Bump to new version in pipeline.json before submitting. ")
              }
            }
          } else {
              def jsonData = readJSON file: "${env.WORKSPACE}/pipeline.json"
              def version_draft = jsonData.version
              def version_check = sh returnStdout: true, script: "curl -f -s ${jsonData.publish_location}/${version_draft} | jq -r .total_count"
              echo "version_draft is $version_draft"
              echo "version_check status is $version_check"
              if (version_check.toInteger() > 0) {
                throw new Exception("Checkout version ${version_draft} already exists!!  Bump to new version in pipeline.json before submitting. ")
              }
          }
        }
      }
    }
    stage('Build Packages') {
      when {
        allOf {
          expression {params.pkgversion != null}
          expression {aigKitchen action: 'isRunKitchenTests'}
          }
        }
      environment {
        HOME = "${env.WORKSPACE}"
        HAB_AUTH_TOKEN = credentials('hab-auth-token')
        PKG_VERSION = "${params.pkgversion}"
      }
      steps {
        script {
          if (env.BRANCH_NAME == 'master') {
            if (params.autobuild == 'true') {
              echo 'Building from master with autobuild options'
              def jsonData = readJSON file: "${env.WORKSPACE}/pipeline.json"
              def latest_pkgversion = sh returnStdout: true, script: "curl ${jsonData.bldrurl}/v1/depot/pkgs/${jsonData.origin}/effortless/latest | jq -j -r .ident.version"
              def pkgversion_major = sh returnStdout: true, script: "echo $latest_pkgversion | cut -d'.' -f1 | tr -d '\\n'"
              def pkgversion_minor = sh returnStdout: true, script: "echo $latest_pkgversion | cut -d'.' -f2 | tr -d '\\n'"
              def pkgversion_patch = sh returnStdout: true, script: "echo $latest_pkgversion | cut -d'.' -f3 | tr -d '\\n'"
              def pkgversion_patchbump = sh returnStdout: true, script: "expr $pkgversion_patch + 1 | tr -d '\\n'"
              def pkgversion_bumpfinal ="${pkgversion_major}.${pkgversion_minor}.${pkgversion_patchbump}"
              env.PKG_VERSION_OVERRIDE = pkgversion_bumpfinal
              echo "Will build with pkgversion ${pkgversion_bumpfinal}"
              sh 'if [ -f kitchen.yml ] ; then mv kitchen.yml kitchen.notused ; fi'
              sh 'mv kitchen.autobuild.yml kitchen.yml'
              sh "echo $HAB_AUTH_TOKEN > hab-build/authtoken"
              sh "echo $PKG_VERSION > hab-build/pkgversion"
              sh 'kitchen converge --color -l debug'
              echo 'notification step should go here to send a message that a new unstable package version has been created and needs to be promoted.'
            } else {
              echo 'Building from current master without autobuild customizations'
              // Obtain pkg version from pipeline.json for master builds which are not autobuild
              def jsonData = readJSON file: "${env.WORKSPACE}/pipeline.json"
              def version_draft = jsonData.version
              echo "version_draft is $version_draft"
              env.PKG_VERSION_OVERRIDE = "$version_draft"
              sh 'if [ -f kitchen.yml ] ; then mv kitchen.yml kitchen.notused ; fi'
              sh 'mv kitchen.habmaster.yml kitchen.yml'
              sh "echo $HAB_AUTH_TOKEN > hab-build/authtoken"
              sh "echo $version_draft > hab-build/pkgversion"
              sh 'kitchen converge --color -c 2'
              echo 'notification step should go here to send a message that a new unstable package version has been created and needs to be promoted.'
            }
          } else {
            echo 'debug for autobuild'
            // Obtain pkg version from pipeline.json
            def jsonData = readJSON file: "${env.WORKSPACE}/pipeline.json"
            def version_draft = jsonData.version
            echo "version_draft is $version_draft"
            env.PKG_VERSION_OVERRIDE = "$version_draft"
            echo 'Running non-master branch steps'
            sh 'if [ -f kitchen.yml ] ; then mv kitchen.yml kitchen.notused ; fi'
            sh 'mv kitchen.habother.yml kitchen.yml'
            sh "echo $HAB_AUTH_TOKEN > hab-build/authtoken"
            sh 'kitchen converge --color -c 2'
            echo 'notification steps will be added in the near future'
          }
        }
      }
      post {
        always {
          sh 'kitchen destroy'
        }
      }
    }
  }
  post {
    success {
      echo 'The build was successful.'
    }
    failure {
      echo 'The build failed'
    }
    always {
      cleanWs()
    }
  }
}
