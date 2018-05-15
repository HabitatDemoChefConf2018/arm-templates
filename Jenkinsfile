// Load in the shared platform jenkins DSL utilities
@Library('platform') _
def repo_version = '0.0.0'
def version(file) {
  def matcher = readFile(file) =~ '"(.+)"'
  matcher ? matcher[0][1] : null
}

node('arm'){
  checkout scm
  stage('Package and Archive'){
    execute "rake publish:package"
    repo_version = version("./VERSION")
    execute "rake utils:git_push_if_needed"

    uploadToArtifactory {
        serverId = 'corp-dev'
        artifactPattern = "arm-nolo-${repo_version}.zip"
        repository = 'azure'
        uploadPath = "nolo/"
    }
  }
}