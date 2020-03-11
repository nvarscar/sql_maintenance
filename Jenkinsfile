pipeline {
  agent {
    node {
      label 'lab'
    }
  }
  stages {
    stage('Install Pester Module') {
      steps {
        powershell 'if (!(get-module pester -ListAvailable)) { install-module pester -Repository PSGallery -Scope CurrentUser -Force }'
      }
    }
    stage('Run tests') {
      steps {
        powershell '& .\\tests\\ci.pester.ps1'
      }
    }
  }
}